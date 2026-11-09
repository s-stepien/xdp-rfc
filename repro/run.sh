#!/bin/bash
# Run inside the test VM as root: ./run.sh <dir-with-shrink.bpf.o>
# Sends large pings over a veth pair whose receiving end runs an XDP
# program that trims all fragments, first in generic then in native mode.
set -u
OBJ="$1/shrink.bpf.o"

dmesg -C
for mode in ${2:-xdpgeneric xdpdrv}; do
	ip netns del a 2>/dev/null
	ip netns add a
	ip link add v0 mtu 9000 type veth peer name v1 mtu 9000 netns a
	ip addr add 10.9.0.1/24 dev v0
	ip -n a addr add 10.9.0.2/24 dev v1
	ip neigh add 10.9.0.2 lladdr $(ip -n a -br link show v1 | awk "{print \$3}") dev v0
	ip link set v0 up
	ip -n a link set v1 up
	if ! ip -n a link set v1 $mode obj "$OBJ" sec xdp.frags; then
		echo "RESULT $mode: failed to attach"
		continue
	fi
	ping -q -c 20 -i 0.05 -W 1 -s 8000 10.9.0.2 >/dev/null 2>&1
	shrunk=$(bpftool map dump name shrink.bss 2>/dev/null | grep -o '"shrunk": [0-9]*' | grep -o '[0-9]*$')
	bad=$(dmesg | grep -c -E "Bad page state|page_pool leak|BUG:|WARNING:")
	echo "RESULT $mode: packets_shrunk=${shrunk:-?} kernel_errors=$bad"
	dmesg | grep -E -A3 "Bad page state|BUG:|WARNING:" | head -20
	dmesg -C
	ip link del v0
done
ip netns del a
