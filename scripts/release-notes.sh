#!/usr/bin/env bash
# Prints the release notes for one version: its "What's new in <version>" section from
# .github/release-notes.md followed by the "Install" section. Exits 1 when the section is missing, so a
# version bump without notes fails CI before it can be tagged.
# Usage: scripts/release-notes.sh [version]   (default: VERSION from the Makefile)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
notes="$root/.github/release-notes.md"
version=${1:-$(sed -n 's/^VERSION[[:space:]]*?=[[:space:]]*//p' "$root/Makefile")}
[ -n "$version" ] || { echo "release-notes: no version given and none in the Makefile" >&2; exit 2; }

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
