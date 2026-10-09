#!/usr/bin/env bash
# The prinbox tmux plugin (the TPM entry): puts the count in the status line where `#{prinbox_status}` stands,
# and binds a key to a popup picker over the inbox (docs/tmux.md). Options, set in tmux.conf before TPM runs:
#   @prinbox_command       the prinbox executable (default prinbox)
#   @prinbox_max_age       seconds the status segment serves the cache (default 60)
#   @prinbox_all           list every pull request you reviewed too (on or off, default off)
#   @prinbox_key           the key after the prefix that opens the popup (default P)
#   @prinbox_popup_width   (default 80%)
#   @prinbox_popup_height  (default 70%)
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)

option() {
    local value
    value=$(tmux show-option -gqv "$1")
    echo "${value:-$2}"
}

command=$(option @prinbox_command prinbox)
max_age=$(option @prinbox_max_age 60)
all=$(option @prinbox_all off)
key=$(option @prinbox_key P)
width=$(option @prinbox_popup_width 80%)
height=$(option @prinbox_popup_height 70%)
segment="#($command inbox --format tmux --max-age $max_age)"

for name in status-left status-right; do
    current=$(tmux show-option -gqv "$name")
    case "$current" in
        *'#{prinbox_status}'*) tmux set-option -gq "$name" "${current//'#{prinbox_status}'/$segment}" ;;
    esac
done

tmux bind-key "$key" display-popup -E -w "$width" -h "$height" \
    "PRINBOX_CMD='$command' PRINBOX_MAX_AGE='$max_age' PRINBOX_ALL='$all' '$dir/tmux/popup.sh'"
