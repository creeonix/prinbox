#!/usr/bin/env bash
# Runs the tests with coverage and fails when PrinboxCore line coverage is below the threshold.
# Usage: scripts/coverage.sh [threshold-percent]
# Extra `swift test` flags come from SWIFT_TEST_FLAGS (the Makefile passes the testing plugin path).
set -euo pipefail

threshold=${1:-80}
# shellcheck disable=SC2086  # SWIFT_TEST_FLAGS is a list of flags
swift test --enable-code-coverage ${SWIFT_TEST_FLAGS:-}
report=$(swift test --show-codecov-path)
jq -r --argjson threshold "$threshold" '
  [.data[0].files[] | select(.filename | contains("/Sources/PrinboxCore/"))] as $files
  | ($files | map(.summary.lines.covered) | add) as $covered
  | ($files | map(.summary.lines.count) | add) as $total
  | ($covered * 100 / $total) as $pct
  | "PrinboxCore line coverage: \((($pct * 10) | floor) / 10)% (\($covered)/\($total) lines)",
    (if $pct < $threshold then "error: below \($threshold)%\n" | halt_error(1) else empty end)
' "$report"
