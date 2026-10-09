#!/usr/bin/env bash
# The tmux plugin's tests: the popup script against the fake fzf and the stub command, and the TPM entry against a
# throwaway tmux server on its own socket.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
here="$root/Tests/Adapters/tmux"
stub="$root/Tests/Adapters/bin/prinbox"
work=$(mktemp -d)
socket="prinbox-test-$$"
cleanup() {
    tmux -L "$socket" kill-server 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

bash -n "$root/prinbox.tmux" "$root/tmux/popup.sh"

printf '#!/usr/bin/env bash\necho "$1" >> "%s/opened"\n' "$work" > "$work/opener"
chmod +x "$work/opener"
export PRINBOX_CMD="$stub" PRINBOX_FZF="$here/fakefzf" PRINBOX_OPENER="$work/opener"
export PRINBOX_STUB_LOG="$work/log" FAKE_FZF_ARGS="$work/fzf-args"

# Enter on the first row opens its URL; fzf saw the delimiter, the columns, the header and the binds.
bash "$root/tmux/popup.sh"
[ "$(cat "$work/opened")" = "https://github.com/acme/web/pull/1290" ]
grep -qx -- '--delimiter' "$work/fzf-args"
grep -qx -- '3,4,5,6,7' "$work/fzf-args"
grep -q 'snooze {1}' "$work/fzf-args"
grep -q 'unsnooze {1}' "$work/fzf-args"
grep -q 'reload(' "$work/fzf-args"
grep -q '^10 waiting on you' "$work/fzf-args"
grep -qx 'inbox lines' "$work/log"
grep -qx 'inbox tmux' "$work/log"

# The 19th line is the snoozed row; a more line would open its ninth field the same way.
rm -f "$work/opened"
FAKE_FZF_PICK=19 bash "$root/tmux/popup.sh"
[ "$(cat "$work/opened")" = "https://github.com/acme/web/pull/1284" ]

# Esc opens nothing.
rm -f "$work/opened"
FAKE_FZF_PICK=0 bash "$root/tmux/popup.sh"
[ ! -f "$work/opened" ]

# Signed out: the setup text, then a wait for Enter (stdin is closed here, so it returns at once), exit 3.
set +e
out=$(PRINBOX_STUB_EXIT=3 bash "$root/tmux/popup.sh" </dev/null); code=$?
set -e
[ "$code" -eq 3 ]
grep -q 'gh auth login' <<<"$out"

# A failed fetch: the rows still show, the header starts with the error.
rm -f "$work/opened"
PRINBOX_STUB_EXIT=1 bash "$root/tmux/popup.sh"
grep -q '^! GitHub did not answer in time' "$work/fzf-args"
[ "$(cat "$work/opened")" = "https://github.com/acme/web/pull/1290" ]

# Without fzf, or without the command: a message and a wait.
out=$(PRINBOX_FZF=/nonexistent/fzf bash "$root/tmux/popup.sh" </dev/null) || true
grep -q 'fzf is not installed' <<<"$out"
out=$(PRINBOX_CMD=/nonexistent/prinbox bash "$root/tmux/popup.sh" </dev/null) || true
grep -q 'prinbox not found' <<<"$out"

# The TPM entry rewrites the status line and binds the key, on a throwaway server.
tmux -L "$socket" -f /dev/null new-session -d -x 80 -y 24
tmux -L "$socket" set-option -g status-right 'left #{prinbox_status} right'
tmux -L "$socket" set-option -g status-left '#{prinbox_status}'
tmux -L "$socket" set-option -g @prinbox_command "$stub"
tmux -L "$socket" set-option -g @prinbox_max_age 30
tmux -L "$socket" run-shell "$root/prinbox.tmux"
[ "$(tmux -L "$socket" show-option -gqv status-right)" = "left #($stub inbox --format tmux --max-age 30) right" ]
[ "$(tmux -L "$socket" show-option -gqv status-left)" = "#($stub inbox --format tmux --max-age 30)" ]
# tmux 3.7's list-keys -T prefix P prints nothing, so filter the table's listing for the key instead.
binding=$(tmux -L "$socket" list-keys -T prefix | grep -E '^bind-key +-T prefix +P ')
grep -q 'display-popup' <<<"$binding"
grep -q 'popup.sh' <<<"$binding"
grep -q "PRINBOX_MAX_AGE='30'" <<<"$binding"
tmux -L "$socket" kill-server
echo "tmux: ok"
