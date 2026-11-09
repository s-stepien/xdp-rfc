#!/bin/bash
# Usage: vm-selftests.sh <kernel tree> <log> <test_progs args...>
# Expects zz-guest-selftests.sh copied into the tree's selftests/bpf dir
# (the guest does not see the host's /tmp).
set -u
TREE="$1"; LOG="$2"; shift 2
cd "$TREE" || exit 1
vng --run arch/x86/boot/bzImage --user root --memory 8G --cpus 8 \
	--rwdir tools/testing/selftests/bpf -- \
	bash tools/testing/selftests/bpf/zz-guest-selftests.sh \
	"$TREE/tools/testing/selftests/bpf" "$@" </dev/null > "$LOG" 2>&1
echo "vng exit=$?"
