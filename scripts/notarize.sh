#!/usr/bin/env bash
# Notarizes one artifact with Apple's notary service and staples the ticket to it when it can carry one.
# A .dmg or .pkg is uploaded as is; an .app or a bare executable is zipped for the upload. The ticket is
# stapled to a .dmg, .pkg or .app; a bare executable cannot hold one, Gatekeeper checks it online.
# A rejected submission prints the notary log, which names the file and the reason, and exits 1.
# Usage: scripts/notarize.sh <artifact> [notarytool credential args...]
#   The credentials default to --keychain-profile prinbox (see RELEASING.md); the release workflow passes
#   --key <.p8> --key-id <id> --issuer <id>.
set -euo pipefail

artifact=${1:?usage: scripts/notarize.sh <artifact> [notarytool credential args...]}
shift
[ -e "$artifact" ] || { echo "notarize: $artifact does not exist" >&2; exit 2; }
[ $# -gt 0 ] || set -- --keychain-profile prinbox

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
upload="$staging/$(basename "$artifact").zip"
case "$artifact" in
    *.dmg|*.pkg) upload=$artifact; staple=1 ;;
    *.app) ditto -c -k --keepParent "$artifact" "$upload"; staple=1 ;;
    *) zip -j -q "$upload" "$artifact"; staple=0 ;;
esac

echo "notarize: submitting $(basename "$upload") and waiting for Apple"
set +e
out=$(xcrun notarytool submit "$upload" "$@" --wait 2>&1)
set -e
printf '%s\n' "$out"
id=$(printf '%s\n' "$out" | sed -n 's/^ *id: //p' | head -1)
status=$(printf '%s\n' "$out" | sed -n 's/^ *status: //p' | tail -1)
if [ "$status" != "Accepted" ]; then
    [ -z "$id" ] || xcrun notarytool log "$id" "$@" >&2 || true
    echo "notarize: $artifact was not accepted (status: ${status:-none})" >&2
    exit 1
fi
[ "$staple" -eq 0 ] || xcrun stapler staple "$artifact"
echo "notarize: $artifact accepted (submission $id)"
