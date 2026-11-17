#!/bin/bash
# Runs in the VM as root: guest-veth.sh <selftests/net dir with lib/xdp_dummy.bpf.o>
cd "$1" || exit 1
echo "KERNEL $(uname -r)"; dmesg -C
./veth.sh
echo "veth.sh rc=$?"
echo "splats=$(dmesg | grep -v 'Spectre V2' | grep -c -E 'Bad page state|page_pool leak|BUG:|WARNING:|underflow|stalled pool')"
