#!/bin/bash
# Tests for lib/deploy-common.sh: the parts of ./deploy that decide something.
# Run: test/deploy-common.test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
. lib/deploy-common.sh

failures=0
check() {
    local name=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s\n     expected: %s\n     actual:   %s\n' "$name" "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

# London wall-clock times as fixed epoch seconds, so the tests need no
# system-specific `date` options and run the same on macOS and Windows.
EVENING_SUMMER=1791489600     # 2026-10-08 21:00 BST
EVENING_WINTER=1796158800     # 2026-12-01 21:00 GMT
AFTER_MIDNIGHT=1791505800     # 2026-10-09 01:30 BST
EXACTLY_0417=1791515820       # 2026-10-09 04:17 BST
CLOCKS_GO_BACK=1792875600     # 2026-10-24 22:00 BST; clocks go back that night
CLOCKS_GO_FORWARD=1774735200  # 2026-03-28 22:00 GMT; clocks go forward that night
london() { node lib/london-time.mjs stamp "$1"; }

# --- when tonight's deploy runs -------------------------------------------
check "evening in summer: next morning at 04:17 BST" \
    "2026-10-09 04:17 BST" "$(london "$(next_overnight_epoch "$EVENING_SUMMER")")"
check "evening in winter: next morning at 04:17 GMT" \
    "2026-12-02 04:17 GMT" "$(london "$(next_overnight_epoch "$EVENING_WINTER")")"
check "prepared after midnight: the same morning" \
    "2026-10-09 04:17 BST" "$(london "$(next_overnight_epoch "$AFTER_MIDNIGHT")")"
check "prepared exactly at 04:17: the next morning, not now" \
    "2026-10-10 04:17 BST" "$(london "$(next_overnight_epoch "$EXACTLY_0417")")"
check "the night the clocks go back: still 04:17 London time" \
    "2026-10-25 04:17 GMT" "$(london "$(next_overnight_epoch "$CLOCKS_GO_BACK")")"
check "the night the clocks go forward: still 04:17 London time" \
    "2026-03-29 04:17 BST" "$(london "$(next_overnight_epoch "$CLOCKS_GO_FORWARD")")"
check "the approval message names the day and zone" \
    "Fri 09 Oct 04:17 BST" "$(london_time "$(next_overnight_epoch "$EVENING_SUMMER")")"
check "the overnight window runs 04:17 to 07:00" "9780" "$OVERNIGHT_WINDOW_SECONDS"

# --- the tested-pair record -----------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
c=1111111111111111111111111111111111111111
s=2222222222222222222222222222222222222222
printf 'client %s\nserver %s\n' "$c" "$s" >"$tmp/pair"
check "record: client commit" "$c" "$(tested_commit "$tmp/pair" client)"
check "record: server commit" "$s" "$(tested_commit "$tmp/pair" server)"
check "record: missing file reads as nothing" "" "$(tested_commit "$tmp/none" client)"
printf 'client abc123\n' >"$tmp/short"
check "record: a short or malformed commit is not accepted" "" "$(tested_commit "$tmp/short" client)"

# --- pending migrations -----------------------------------------------------
check "migrations: none to apply" "" "$(printf '✅ No migrations to apply!\n' | pending_migrations)"
list=$(printf '%s\n' \
    'Migrations to be applied:' \
    '┌──────────────────────────────┐' \
    '│ Name                         │' \
    '│ 0041_add_collection_notes.sql │' \
    '│ 0042_index-sessions.sql      │' \
    '└──────────────────────────────┘' | pending_migrations | tr '\n' ' ')
check "migrations: names read from the table" "0041_add_collection_notes.sql 0042_index-sessions.sql " "$list"

# --- JSON -------------------------------------------------------------------
check "json: bookmark read" "00000085-0000024c" "$(printf '{"bookmark":"00000085-0000024c","timestamp":"x"}' | json_field bookmark)"
check "json: version read" "abc1234" "$(printf '{"status":"ok","version":"abc1234"}' | json_field version)"
json_field version <<<'not json' >/dev/null 2>&1
check "json: invalid input fails" "1" "$?"
json_field version <<<'{"version":""}' >/dev/null 2>&1
check "json: an empty value fails" "1" "$?"

# --- settings and email -----------------------------------------------------
printf 'TARGET=uat\r\nSTATUS=waiting\r\n' >"$tmp/crlf"
check "settings: a Windows line ending is not part of the value" "uat" "$(read_setting "$tmp/crlf" TARGET)"
printf 'TARGET=uat\nSTATUS=waiting\n' >"$tmp/state"
write_setting "$tmp/state" STATUS running
write_setting "$tmp/state" BOOKMARK 0000abcd
check "settings: a value is replaced in place" "running" "$(read_setting "$tmp/state" STATUS)"
check "settings: a new key is added" "0000abcd" "$(read_setting "$tmp/state" BOOKMARK)"
check "settings: other keys are kept" "uat" "$(read_setting "$tmp/state" TARGET)"

printf 'RESEND_FROM=Food bank <releases@example.org>\nRESEND_TO=a@example.org, b@example.org\n' >"$tmp/settings"
check "settings: value with spaces and =" "Food bank <releases@example.org>" "$(read_setting "$tmp/settings" RESEND_FROM)"
check "settings: missing key reads as nothing" "" "$(read_setting "$tmp/settings" NOPE)"
check "email: recipients split and trimmed, text escaped" \
    '{"from":"f@x","to":["a@x","b@x"],"subject":"S \"q\"","text":"line 1\nline 2"}' \
    "$(email_json f@x 'a@x, b@x' 'S "q"' $'line 1\nline 2')"
email_json f@x ' , ' s t >/dev/null 2>&1
check "email: no recipients fails" "1" "$?"

# --- the record ./push writes is the record ./deploy reads -------------------
write_tested_record "$tmp/written" "$c" "$s"
check "written record: client reads back" "$c" "$(tested_commit "$tmp/written" client)"
check "written record: server reads back" "$s" "$(tested_commit "$tmp/written" server)"
check "written record: no temporary file left" "1" "$(ls "$tmp" | grep -c '^written')"
check "write_setting leaves no temporary file" "1" "$(ls "$tmp" | grep -c '^state')"

# --- where a branch stands against GitHub ------------------------------------
repo="$tmp/repo"
git init -q "$repo"
commit() { git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1"; git -C "$repo" rev-parse HEAD; }
base=$(commit base)
ahead=$(commit ahead)
git -C "$repo" checkout -q -b other "$base"
other=$(commit other)
check "position: same" "same" "$(branch_position "$repo" "$ahead" "$ahead")"
check "position: ahead of GitHub" "ahead" "$(branch_position "$repo" "$ahead" "$base")"
check "position: behind GitHub" "behind" "$(branch_position "$repo" "$base" "$ahead")"
check "position: diverged" "diverged" "$(branch_position "$repo" "$other" "$ahead")"

echo
if [ "$failures" -gt 0 ]; then
    echo "$failures failed"
    exit 1
fi
echo "all passed"
