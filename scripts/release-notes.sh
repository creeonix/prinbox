#!/usr/bin/env bash
# Prints the release notes for one version: its "What's new in <version>" section from
# .github/release-notes.md followed by the "Install" section. Exits 1 when the section is missing or when the
# command's Version.swift disagrees, so a bump in one place fails CI.
# Usage: scripts/release-notes.sh [version]   (default: VERSION from the Makefile)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
notes="$root/.github/release-notes.md"
version=${1:-$(sed -n 's/^VERSION[[:space:]]*?=[[:space:]]*//p' "$root/Makefile")}
[ -n "$version" ] || { echo "release-notes: no version given and none in the Makefile" >&2; exit 2; }
cli_version=$(sed -n 's/^[[:space:]]*static let number = "\(.*\)"$/\1/p' "$root/Sources/PrinboxCLI/Version.swift")
if [ "$cli_version" != "$version" ]; then
    echo "release-notes: Sources/PrinboxCLI/Version.swift says \"$cli_version\", expected \"$version\"" >&2
    exit 1
fi

# Prints one level-2 section (heading included) up to the next level-2 heading.
section() {
    awk -v heading="## $1" '
        $0 == heading { on = 1; print; next }
        /^## / { on = 0 }
        on { print }
    ' "$notes"
}

whats_new=$(section "What's new in $version")
if [ -z "$whats_new" ]; then
    echo "release-notes: no \"## What's new in $version\" section in $notes" >&2
    exit 1
fi
printf '%s\n\n' "$whats_new"
section "Install"
