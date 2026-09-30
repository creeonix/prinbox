#!/usr/bin/env bash
# Records the live inbox as an anonymized two-phase test fixture: the search response and the details batches.
# Usage: scripts/record-fixture.sh <name>
# Writes Tests/PrinboxCoreTests/Fixtures/<name>.json as {"search": ..., "details": [...]}. scripts/anonymize.jq
# replaces repositories, logins, titles, urls, ids and branch names, so no private data is committed.
set -euo pipefail

name=${1:?usage: scripts/record-fixture.sh <name>}
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/Tests/PrinboxCoreTests/Fixtures/$name.json"

query=$(swift run --package-path "$root" -q Prinbox --print-query)
template=$(swift run --package-path "$root" -q Prinbox --print-details-query)
# gh exits 1 when the response carries GraphQL errors but still prints the body, so keep it.
search=$(gh api graphql -f query="$query") || true
[ -n "$search" ] || { echo "gh returned nothing for the search" >&2; exit 1; }

details='[]'
ids=$(jq -r '[.data | (.review, .mentions, .mine, .involved) | .nodes[]? | select(. != null and .id != null) | .id] | unique | .[]' <<<"$search")
while read -r -a batch; do
    [ "${#batch[@]}" -gt 0 ] || continue
    list=$(printf '"%s", ' "${batch[@]}")
    list=${list%, }
    part=$(gh api graphql -f query="${template//__IDS__/$list}") || true
    [ -n "$part" ] || { echo "gh returned nothing for a details batch" >&2; exit 1; }
    details=$(jq -c --argjson part "$part" '. + [$part]' <<<"$details")
done < <(printf '%s\n' $ids | xargs -n 10)

jq -n --argjson search "$search" --argjson details "$details" '{search: $search, details: $details}' \
    | jq -f "$root/scripts/anonymize.jq" > "$out"
echo "wrote $out"
