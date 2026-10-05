#!/usr/bin/env bash
# Writes the Homebrew cask (the app) and formula (the command) for one release into a checkout of
# creeonix/homebrew-tap, commits and pushes. The checksums come from the release's .sha256 files: downloaded
# with gh, or read from --from-dir (the release workflow passes its build/). --dry-run prints both files.
# Usage: scripts/update-tap.sh <version> [--from-dir <dir>] [--dry-run]   TAP_DIR defaults to ../homebrew-tap
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
version=${1:?usage: scripts/update-tap.sh <version> [--from-dir <dir>] [--dry-run]}
shift
from_dir=""
dry_run=0
while [ $# -gt 0 ]; do
    case "$1" in
        --from-dir) from_dir=${2:?--from-dir needs a directory}; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        *) echo "update-tap: unknown option $1" >&2; exit 2 ;;
    esac
done
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*([-.][0-9A-Za-z.]+)?$ ]] || {
    echo "update-tap: '$version' is not a version (no leading v, digits and dots)" >&2
    exit 2
}
tap_dir=${TAP_DIR:-$root/../homebrew-tap}
dmg="PRInbox-$version.dmg"
tarball="prinbox-$version-macos.tar.gz"

if [ -z "$from_dir" ]; then
    from_dir=$(mktemp -d)
    trap 'rm -rf "$from_dir"' EXIT
    gh release download "v$version" --repo creeonix/prinbox --pattern '*.sha256' --dir "$from_dir"
fi
sha() { awk '{print $1}' "$from_dir/$1.sha256" 2>/dev/null || true; }
dmg_sha=$(sha "$dmg")
cli_sha=$(sha "$tarball")
[ "${#dmg_sha}" -eq 64 ] && [ "${#cli_sha}" -eq 64 ] || { echo "update-tap: checksums not found in $from_dir" >&2; exit 1; }

render() {
    sed -e "s/@VERSION@/$version/g" -e "s/@DMG_SHA256@/$dmg_sha/g" -e "s/@CLI_SHA256@/$cli_sha/g" \
        "$root/packaging/homebrew/$1"
}

if [ "$dry_run" -eq 1 ]; then
    render prinbox.rb
    echo
    render prinbox-cli.rb
    exit 0
fi
[ -d "$tap_dir/.git" ] || { echo "update-tap: no tap checkout at $tap_dir (set TAP_DIR)" >&2; exit 1; }
mkdir -p "$tap_dir/Casks" "$tap_dir/Formula"
render prinbox.rb > "$tap_dir/Casks/prinbox.rb"
render prinbox-cli.rb > "$tap_dir/Formula/prinbox-cli.rb"
git -C "$tap_dir" add Casks/prinbox.rb Formula/prinbox-cli.rb
if git -C "$tap_dir" diff --cached --quiet; then
    if [ -n "$(git -C "$tap_dir" rev-list @{u}..HEAD 2>/dev/null)" ]; then
        git -C "$tap_dir" push
        echo "tap pushed $version"
        exit 0
    fi
    echo "tap already at $version"
    exit 0
fi
git -C "$tap_dir" commit -m "prinbox $version"
git -C "$tap_dir" push
echo "tap updated to $version"
