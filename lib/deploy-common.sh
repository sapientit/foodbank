# Shared functions for ./deploy. Sourced, never run.
#
# Kept apart from the command itself so the parts that decide something — when
# tonight's deploy runs, which migrations are pending, whether a pair matches
# the tested record — can be tested on their own (test/deploy-common.test.sh)
# without touching git, Cloudflare or the network.

# Overnight deploys start at this London time: clear of the server's 02:17 UTC
# nightly job in both seasons (02:17 or 03:17 London) and before 07:00.
OVERNIGHT_LONDON_TIME=04:17
# From 04:17 to 07:00. An overnight deploy that has not started by then does
# not start at all.
OVERNIGHT_WINDOW_SECONDS=$(( (7 * 60 - (4 * 60 + 17)) * 60 ))

die() {
    echo "STOPPED: $*" >&2
    exit 1
}

say() { printf '%s\n' "$*"; }
heading() { printf '\n== %s ==\n' "$*"; }

COMMON_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# The epoch second of the next OVERNIGHT_LONDON_TIME in Europe/London strictly
# after $1 (an epoch second; defaults to now). Prepared at 21:00 it is tomorrow
# morning; prepared at 01:00 it is the same morning, three hours later. Node,
# not `date`, because macOS's and Git Bash's `date` take different options.
next_overnight_epoch() {
    node "$COMMON_LIB_DIR/london-time.mjs" next "$OVERNIGHT_LONDON_TIME" "${1:-$(date +%s)}"
}

london_time() { node "$COMMON_LIB_DIR/london-time.mjs" format "$1"; }

# Reads one commit from the tested-pair record that the push command writes:
#   client <full sha>
#   server <full sha>
# Prints nothing when the record or the line is missing.
tested_commit() {
    local record=$1 which=$2
    [ -f "$record" ] || return 0
    awk -v k="$which" '$1 == k && $2 ~ /^[0-9a-f]{40}$/ { print $2; exit }' "$record"
}

# Migration file names in `wrangler d1 migrations list` output, one per line.
# Prints nothing when there are none to apply.
pending_migrations() {
    # grep uses status 1 for a normal no-match result. Under the deploy
    # command's pipefail setting, normalise that result so no pending
    # migrations does not stop deployment preparation.
    { grep -oE '[0-9]{4}_[A-Za-z0-9_.-]+\.sql' || [ "$?" -eq 1 ]; } | awk '!seen[$0]++'
}

# The bookmark from `wrangler d1 time-travel info --json`, or nothing.
json_field() {
    node -e '
        let v;
        try { v = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch { process.exit(1); }
        for (const k of process.argv[1].split(".")) v = v === null || typeof v !== "object" ? undefined : v[k];
        if (typeof v !== "string" || v === "") process.exit(1);
        process.stdout.write(v);
    ' "$1"
}

# Sets KEY=value in a state file, in place, the same way on every system.
write_setting() {
    local file=$1 key=$2 value=$3 tmp
    tmp=$(mktemp "$file.XXXXXX")
    awk -F= -v k="$key" -v v="$value" '$1 == k { print k "=" v; done = 1; next } { print } END { if (!done) print k "=" v }' "$file" >"$tmp"
    mv "$tmp" "$file"
}

# Reads KEY=value lines from a state or settings file without executing it.
read_setting() {
    local file=$1 key=$2
    [ -f "$file" ] || return 0
    # A file saved by a Windows editor ends its lines with CR; drop it.
    awk -F= -v k="$key" '{ sub(/\r$/, "") } $1 == k { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

# The Resend request body, built by node so every value is escaped correctly.
email_json() {
    local from=$1 to=$2 subject=$3 body=$4
    node -e '
        const [from, to, subject, text] = process.argv.slice(1);
        const recipients = to.split(",").map((s) => s.trim()).filter(Boolean);
        if (recipients.length === 0) process.exit(1);
        process.stdout.write(JSON.stringify({ from, to: recipients, subject, text }));
    ' "$from" "$to" "$subject" "$body"
}

# Writes the tested-pair record that ./deploy reads (see tested_commit), in one
# step, so a half-written record can never be read.
write_tested_record() {
    local record=$1 client=$2 server=$3 tmp
    tmp=$(mktemp "$record.XXXXXX")
    printf '# Written by ./push after both repositories passed their full checks, %s\nclient %s\nserver %s\n' \
        "$(date -u +%Y-%m-%dT%H:%MZ)" "$client" "$server" >"$tmp"
    mv "$tmp" "$record"
}

# How a local branch stands against GitHub's copy: same, ahead, behind or
# diverged. Arguments are two commits: local, then remote.
branch_position() {
    local dir=$1 local_sha=$2 remote_sha=$3
    if [ "$local_sha" = "$remote_sha" ]; then
        echo same
    elif git -C "$dir" merge-base --is-ancestor "$remote_sha" "$local_sha"; then
        echo ahead
    elif git -C "$dir" merge-base --is-ancestor "$local_sha" "$remote_sha"; then
        echo behind
    else
        echo diverged
    fi
}

# The hooks in githooks/ that the secondary machine's bootstrap installs in
# both application repositories. The path is relative to each repository, so
# it is the same on every system.
SECONDARY_HOOKS_PATH=../githooks

# Succeeds when a repository runs the secondary machine's hooks.
secondary_hooks_installed() {
    [ "$(git -C "$1" config --get core.hooksPath)" = "$SECONDARY_HOOKS_PATH" ]
}
