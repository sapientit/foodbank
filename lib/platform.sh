# The few things ./push, ./deploy and ./check-setup do differently on macOS and
# on Windows. Sourced, never run. Everything else in those commands is the
# same on both: on Windows they run in Git Bash, which Git for Windows brings.

platform() {
    case "$(uname -s)" in
        Darwin) echo mac ;;
        MINGW* | MSYS* | CYGWIN*) echo windows ;;
        *) echo unsupported ;;
    esac
}

require_supported_platform() {
    [ "$(platform)" != unsupported ] ||
        die "this runs on macOS, or on Windows in Git Bash. $(uname -s) is not supported."
}

_windows_ps() {
    local script
    script=$(cygpath -w "$PLATFORM_LIB_DIR/windows-credential.ps1")
    # -ExecutionPolicy Bypass applies to this one call only; Windows blocks
    # unsigned script files by default.
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$script" "$@"
}

PLATFORM_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Prints the secret stored under a name, or fails. The value goes to stdout
# for the caller to capture; it is never echoed, logged or put on a command
# line.
read_secret() {
    local name=$1
    case "$(platform)" in
        mac) security find-generic-password -a "$USER" -s "$name" -w 2>/dev/null ;;
        windows) _windows_ps -Action Read -Target "$name" 2>/dev/null | tr -d '\r' ;;
        *) return 1 ;;
    esac
}

# Prompts the person for a secret, without showing it, and stores it.
store_secret() {
    local name=$1
    case "$(platform)" in
        mac) security add-generic-password -U -a "$USER" -s "$name" -w ;;
        windows) _windows_ps -Action Write -Target "$name" </dev/tty ;;
        *) return 1 ;;
    esac
}

# Where a person looks to see or remove a stored secret.
secret_store_name() {
    case "$(platform)" in
        mac) echo "the keychain" ;;
        windows) echo "Windows Credential Manager" ;;
        *) echo "the credential store" ;;
    esac
}

# Keeps the machine from sleeping until the given process ends. On Windows the
# keep-awake process watches a marker file instead, removed by the deploy's
# exit trap, because Git Bash and Windows number processes differently.
keep_awake_while_running() {
    local pid=$1 marker=$2
    case "$(platform)" in
        mac) caffeinate -ims -w "$pid" >/dev/null 2>&1 & ;;
        windows)
            : >"$marker"
            _windows_ps -Action KeepAwake -Marker "$(cygpath -w "$marker")" >/dev/null 2>&1 &
            ;;
    esac
}

# npm runs package scripts with cmd.exe on Windows, and both repositories'
# scripts are written for a Unix shell. Point npm at Git's bash for anything
# these commands run.
use_bash_for_npm_scripts() {
    if [ "$(platform)" = windows ]; then
        local bash_exe
        bash_exe=$(cygpath -w "$(command -v bash)")
        export npm_config_script_shell="$bash_exe"
    fi
}

# Register a local daily operating-system task, rather than a repository cron
# file. The task only runs the read-only test D1 probe.
schedule_test_d1_probe() {
    local project_dir=$1
    case "$(platform)" in
        mac)
            local user_dir label agent uid
            label=org.guildfordfoodbank.test-d1-probe
            user_dir=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')
            agent="$user_dir/Library/LaunchAgents/$label.plist"
            uid=$(id -u)
            node -e '
const fs = require("fs");
const [file, project] = process.argv.slice(1);
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
fs.writeFileSync(file, `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>Label</key><string>org.guildfordfoodbank.test-d1-probe</string><key>ProgramArguments</key><array><string>/bin/bash</string><string>${esc(project)}/probe-test-d1</string></array><key>StartCalendarInterval</key><dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>17</integer></dict><key>StandardOutPath</key><string>${esc(project)}/.deploy/test-d1-probe-launchd.log</string><key>StandardErrorPath</key><string>${esc(project)}/.deploy/test-d1-probe-launchd.log</string></dict></plist>\n`);
' "$agent" "$project_dir"
            launchctl bootout "gui/$uid" "$agent" >/dev/null 2>&1 || true
            launchctl bootstrap "gui/$uid" "$agent"
            ;;
        windows)
            _windows_ps -Action ScheduleTestD1Probe -ProjectDir "$(cygpath -w "$project_dir")" -BashPath "$(cygpath -w "$(command -v bash)")"
            ;;
    esac
}
