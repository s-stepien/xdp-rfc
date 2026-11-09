#!/bin/bash
# Usage: run-in-vm.sh <kernel tree with a built bzImage> <guest script> [log]
# Boots the tree's kernel in virtme-ng and runs <guest script> from this
# directory as root, passing this directory as its first argument.
# Example: ./run-in-vm.sh ~/projekty/linux cov.sh cov.log
set -u
TESTS=$(dirname "$(readlink -f "$0")")
TREE=$(readlink -f "$1"); SCRIPT="$2"; LOG="${3:-/dev/stdout}"
cd "$TREE" || exit 1
timeout 600 vng -r arch/x86/boot/bzImage --user root --memory 4G --cpus 2 \
	--rwdir "$TESTS" -- bash "$TESTS/$SCRIPT" "$TESTS" </dev/null > "$LOG" 2>&1
echo "vng exit=$?"
