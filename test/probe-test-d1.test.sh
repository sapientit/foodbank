#!/bin/bash
# Run: test/probe-test-d1.test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
mkdir -p "$project/lib" "$project/foodbankserver/node_modules/.bin"
cp probe-test-d1 "$project/probe-test-d1"
cp lib/deploy-common.sh lib/london-time.mjs "$project/lib/"
chmod +x "$project/probe-test-d1"
cat >"$project/foodbankserver/node_modules/.bin/npx" <<'EOF'
#!/bin/bash
[ "${CLOUDFLARE_API_TOKEN+x}" = x ] && exit 91
[ "${CLOUDFLARE_ACCOUNT_ID+x}" = x ] && exit 92
shift
case "$1 $2" in
  'whoami ') printf '│ Personal │ ea7ad751ffa489bc577330c6eedd7500 │\n' ;;
  'd1 list') printf '[{"name":"foodbank-test"}]\n' ;;
  'd1 migrations') printf '✅ No migrations to apply!\n' ;;
  *) exit 93 ;;
esac
EOF
chmod +x "$project/foodbankserver/node_modules/.bin/npx"

output=$(PATH="$project/foodbankserver/node_modules/.bin:$PATH" CLOUDFLARE_API_TOKEN=must-not-leak CLOUDFLARE_ACCOUNT_ID=must-not-leak "$project/probe-test-d1")
printf '%s\n' "$output" | grep -qx 'PROBE OK'
printf '%s\n' "$output" | grep -q 'Wrangler account: ea7ad751ffa489bc577330c6eedd7500 (expected test account)'
printf '%s\n' "$output" | grep -q 'Pending-migrations check: no migrations to apply'
log=$(find "$project/.deploy" -name 'test-d1-probe-*.log' -type f)
[ -n "$log" ]
! grep -q 'must-not-leak' "$log"
echo 'all passed'
