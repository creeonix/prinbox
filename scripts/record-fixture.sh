#!/usr/bin/env bash
# Records the live inbox query as an anonymized test fixture.
# Usage: scripts/record-fixture.sh <name>
# Writes Tests/PrinboxCoreTests/Fixtures/<name>.json. scripts/anonymize.jq replaces repositories,
# logins, titles, urls and ids, so no private org data is committed.
set -euo pipefail

name=${1:?usage: scripts/record-fixture.sh <name>}
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/Tests/PrinboxCoreTests/Fixtures/$name.json"

query=$(swift run --package-path "$root" -q Prinbox --print-query)
# gh exits 1 when the response carries GraphQL errors but still prints the body, so keep it.
raw=$(gh api graphql -f query="$query") || true
if [ -z "$raw" ]; then
    echo "gh returned nothing" >&2
    exit 1
fi
jq -f "$root/scripts/anonymize.jq" <<<"$raw" > "$out"
echo "wrote $out"
