#!/usr/bin/env bash
# Records the live inbox as an anonymized two-phase test fixture: the search response and the details batches.
# Usage: scripts/record-fixture.sh <name>
# Writes Tests/PrinboxCoreTests/Fixtures/<name>.json as {"search": ..., "details": [...]}. scripts/anonymize.jq
# replaces repositories, logins, titles, urls, ids and branch names, so no private data is committed.
set -euo pipefail

name=${1:?usage: scripts/record-fixture.sh <name>}
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/Tests/PrinboxCoreTests/Fixtures/$name.json"

query=$(swift run --package-path "$root" -q PrinboxApp --print-query)
template=$(swift run --package-path "$root" -q PrinboxApp --print-details-query)
# gh exits 1 when the response carries GraphQL errors but still prints the body, so keep it.
search=$(gh api graphql -f query="$query") || true
[ -n "$search" ] || { echo "gh returned nothing for the search" >&2; exit 1; }

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
count=0
ids=$(jq -r '[.data | (.review, .mentions, .mine, .involved) | .nodes[]? | select(. != null and .id != null) | .id] | unique | .[]' <<<"$search")
while read -r -a batch; do
    [ "${#batch[@]}" -gt 0 ] || continue
    for id in "${batch[@]}"; do
        [[ "$id" =~ ^[A-Za-z0-9_=-]+$ ]] || { echo "record-fixture: stopping: an id that is not a node id" >&2; exit 1; }
    done
    list=$(printf '"%s", ' "${batch[@]}")
    list=${list%, }
    part=$(gh api graphql -f query="${template//__IDS__/$list}") || true
    [ -n "$part" ] || { echo "gh returned nothing for a details batch" >&2; exit 1; }
    count=$((count + 1))
    printf '%s\n' "$part" > "$(printf '%s/part-%03d.json' "$dir" "$count")"
done < <(printf '%s\n' $ids | xargs -n 10)

if [ "$count" -gt 0 ]; then jq -s '.' "$dir"/part-*.json > "$dir/details.json"; else echo '[]' > "$dir/details.json"; fi

jq -n --argjson search "$search" --slurpfile details "$dir/details.json" '{search: $search, details: $details[0]}' \
    | jq -f "$root/scripts/anonymize.jq" > "$out"
echo "wrote $out"
