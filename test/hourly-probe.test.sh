#!/bin/bash
# Run: test/hourly-probe.test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp probe-test-d1-hourly start-hourly-test-d1-probe stop-hourly-test-d1-probe "$tmp/"
cat >"$tmp/probe-test-d1" <<'EOF'
#!/bin/bash
echo PROBE-RAN
EOF
chmod +x "$tmp/probe-test-d1" "$tmp/probe-test-d1-hourly" "$tmp/start-hourly-test-d1-probe" "$tmp/stop-hourly-test-d1-probe"

"$tmp/start-hourly-test-d1-probe" >/dev/null
pid=$(cat "$tmp/.deploy/test-d1-probe-hourly.pid")
for _ in 1 2 3 4 5; do
    grep -q '^PROBE-RAN$' "$tmp/.deploy/test-d1-probe-hourly.log" 2>/dev/null && break
    sleep 1
done
grep -qx 'PROBE-RAN' "$tmp/.deploy/test-d1-probe-hourly.log"
kill -0 "$pid"
"$tmp/stop-hourly-test-d1-probe" >/dev/null
[ ! -e "$tmp/.deploy/test-d1-probe-hourly.pid" ]
! kill -0 "$pid" 2>/dev/null
echo 'all passed'
