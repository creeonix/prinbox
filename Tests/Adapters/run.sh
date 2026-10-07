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

# Tasks 9 to 11 add their suites here, each guarded by `command -v <tool>`.

[ "$failed" -eq 0 ] || exit 1
echo "adapter suites run: $ran"
