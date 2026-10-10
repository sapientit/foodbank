#!/bin/bash
# Tests the private-snapshot gate without creating a real database or reading
# a real export. Run: test/require-seed.test.sh
set -u

cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
mkdir -p "$project"
cp require-seed "$project/require-seed"
cp restore-local-database "$project/restore-local-database"
chmod +x "$project/require-seed"
chmod +x "$project/restore-local-database"

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

"$project/require-seed" >"$tmp/out" 2>"$tmp/err"
check "missing snapshot stops setup" "1" "$?"
grep -q 'Do not create an empty database' "$tmp/err"
check "missing snapshot explains the safe next step" "0" "$?"

mkdir "$project/foodbankserver"
"$project/restore-local-database" >"$tmp/out" 2>"$tmp/err"
check "guarded restore stops without snapshot" "1" "$?"
grep -q 'Do not create an empty database' "$tmp/err"
check "guarded restore does not bypass snapshot gate" "0" "$?"

mkdir "$project/seed"
: >"$project/seed/uat.sql"
"$project/require-seed" >"$tmp/out" 2>"$tmp/err"
check "empty snapshot stops setup" "1" "$?"

printf 'not a real export; only the gate is under test\n' >"$project/seed/uat.sql"
"$project/require-seed" >"$tmp/out" 2>"$tmp/err"
check "present snapshot allows setup" "0" "$?"

if [ "$failures" -gt 0 ]; then
    exit 1
fi
printf '\nall passed\n'
