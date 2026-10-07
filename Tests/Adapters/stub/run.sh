#!/usr/bin/env bash
# Pins the stub's contract, which the three adapter suites build on.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
stub="$root/Tests/Adapters/bin/prinbox"
golden="$root/Tests/PrinboxCoreTests/Golden"
log=$(mktemp)
err=$(mktemp)
trap 'rm -f "$log" "$err"' EXIT

diff <("$stub" inbox --format json) "$golden/demo-inbox.json"
diff <("$stub" inbox --cached --format lines) "$golden/demo-inbox.lines"
[ "$("$stub" inbox --format tmux --max-age 60)" = "8" ]
[ "$("$stub" --version)" = "prinbox 0.7.0-stub" ]

PRINBOX_STUB_LOG=$log "$stub" snooze DEMO_1290
PRINBOX_STUB_LOG=$log "$stub" unsnooze DEMO_1290
PRINBOX_STUB_LOG=$log "$stub" open DEMO_58
PRINBOX_STUB_LOG=$log "$stub" inbox --cached --format json > /dev/null
[ "$(cat "$log")" = $'snooze DEMO_1290\nunsnooze DEMO_1290\nopen DEMO_58\ninbox json' ]

set +e
out=$(PRINBOX_STUB_EXIT=3 "$stub" inbox 2> "$err"); code=$?
set -e
[ "$code" -eq 3 ]
[ "$out" = "$(cat "$golden/setup-needed.json")" ]
grep -q 'gh auth login' "$err"

set +e
out=$(PRINBOX_STUB_EXIT=1 "$stub" inbox --format json 2> "$err"); code=$?
set -e
[ "$code" -eq 1 ]
[ "$out" = "$(cat "$golden/fetch-failed.json")" ]
grep -q 'did not answer' "$err"
[ "$(PRINBOX_STUB_EXIT=1 "$stub" inbox --format tmux 2>/dev/null || true)" = "!8" ]

PRINBOX_STUB_VERSION=2 "$stub" inbox | grep -q '"version" : 2,'

set +e
"$stub" inbox --format waybar 2>/dev/null; code=$?
set -e
[ "$code" -eq 2 ]
echo "stub: ok"
