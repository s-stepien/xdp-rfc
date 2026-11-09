#!/bin/bash
# Runs inside the VM: guest-selftests.sh <selftests dir> <test_progs args...>
# With "xsk" as the only test argument, runs the standalone test_xsk.sh suite.
cd "$1" || exit 1; shift
mountpoint -q /sys/fs/bpf || mount -t bpf bpffs /sys/fs/bpf
if [ "$*" = xsk ]; then
	./test_xsk.sh
	echo "test_xsk.sh rc=$?"
else
	./test_progs "$@"
fi
echo "=== dmesg splats ==="
dmesg | grep -v "Spectre V2" | grep -E -c "Bad page state|page_pool leak|BUG:|WARNING:|underflow|stalled pool"
dmesg | grep -v "Spectre V2" | grep -E -A12 "Bad page state|page_pool leak|BUG:|WARNING:|stalled pool" | head -80
