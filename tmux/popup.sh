#!/usr/bin/env bash
# The picker inside the tmux popup: the inbox's rows through fzf. Enter opens the row's URL (a more line opens its
# section page), ctrl-s and ctrl-u snooze and wake through the command and reload, ctrl-r refetches. Environment:
# PRINBOX_CMD (prinbox), PRINBOX_MAX_AGE (60), PRINBOX_FZF (fzf), PRINBOX_OPENER (open on Darwin, else xdg-open).
# No `set -e`: a failed step must say why, not vanish with the popup.
set -uo pipefail
cmd=${PRINBOX_CMD:-prinbox}
max_age=${PRINBOX_MAX_AGE:-60}
fzf=${PRINBOX_FZF:-fzf}
opener=${PRINBOX_OPENER:-}
if [ -z "$opener" ]; then
    if [ "$(uname)" = Darwin ]; then opener=open; else opener=xdg-open; fi
fi

pause() {
    printf '%s\n\nPress Enter to close.' "$1"
    read -r _ || true
}

command -v "$fzf" >/dev/null 2>&1 || { pause "prinbox: fzf is not installed (brew install fzf)"; exit 1; }
command -v "$cmd" >/dev/null 2>&1 || { pause "prinbox not found: brew install creeonix/tap/prinbox-cli"; exit 1; }

errors=$(mktemp)
trap 'rm -f "$errors"' EXIT
rows=$("$cmd" inbox --max-age "$max_age" --format lines 2>"$errors")
code=$?
case "$code" in
    0|1) ;;
    *) pause "$(cat "$errors")"; exit "$code" ;;
esac
count=$("$cmd" inbox --cached --format tmux 2>/dev/null)
header="${count:-0} waiting on you · enter open  ^s snooze  ^u unsnooze  ^r refresh"
if [ "$code" -eq 1 ]; then
    header="! $(head -n1 "$errors" | sed 's/^prinbox: //') · $header"
fi
reload="$cmd inbox --cached --format lines"
selection=$(printf '%s\n' "$rows" | "$fzf" --delimiter '\t' --with-nth 3,4,5,6,7 --no-sort --header "$header" \
    --bind "ctrl-s:execute-silent($cmd snooze {1})+reload($reload)" \
    --bind "ctrl-u:execute-silent($cmd unsnooze {1})+reload($reload)" \
    --bind "ctrl-r:reload($cmd inbox --format lines)")
[ -n "$selection" ] || exit 0
url=$(printf '%s\n' "$selection" | cut -f9)
[ -n "$url" ] && "$opener" "$url"
exit 0
