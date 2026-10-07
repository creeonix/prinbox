#!/usr/bin/env bash
# Runs the adapter suites whose tool is installed (the stub's own test always; Neovim 0.10+, Emacs 29+, tmux with
# fzf when present) and says what it skipped. Exit 1 when a suite that ran failed. `make test-adapters` calls it.
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
failed=0
ran=0

run_suite() {
    local name=$1
    shift
    echo "== $name"
    if "$@"; then
        echo "$name: ok"
        ran=$((ran + 1))
    else
        echo "$name: FAILED"
        failed=1
    fi
}

run_suite stub bash "$root/Tests/Adapters/stub/run.sh"

if command -v nvim >/dev/null 2>&1; then
    run_suite neovim nvim --clean -l "$root/Tests/Adapters/nvim/run.lua"
else
    echo "neovim: skipped (nvim not installed)"
fi

if command -v emacs >/dev/null 2>&1; then
    run_suite emacs-compile emacs --batch -Q --eval "(setq byte-compile-error-on-warn t)" \
        -f batch-byte-compile "$root/prinbox.el"
    rm -f "$root/prinbox.elc"
    run_suite emacs emacs --batch -Q -L "$root" -l ert -l "$root/Tests/Adapters/emacs/prinbox-test.el" \
        -f ert-run-tests-batch-and-exit
else
    echo "emacs: skipped (emacs not installed)"
fi

if command -v tmux >/dev/null 2>&1; then
    run_suite tmux bash "$root/Tests/Adapters/tmux/run.sh"
else
    echo "tmux: skipped (tmux not installed)"
fi

[ "$failed" -eq 0 ] || exit 1
echo "adapter suites run: $ran"
