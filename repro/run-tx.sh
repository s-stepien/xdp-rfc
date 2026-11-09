#!/bin/bash
# Run inside the test VM as root: ./run-tx.sh <dir> <prog>
# Native XDP on v1 bounces large pings back to v0 via XDP_TX; v0 runs an
# XDP_PASS program so its NAPI accepts xdp_frames from the peer.
set -u
OBJ="$1/tx.bpf.o"
PROG="$2"

dmesg -C
ip netns add a
ip link add v0 mtu 9000 type veth peer name v1 mtu 9000 netns a
ip addr add 10.9.0.1/24 dev v0
ip -n a addr add 10.9.0.2/24 dev v1
ip link set v0 up
ip -n a link set v1 up
ip link set v0 xdpdrv obj "$OBJ" program xdp_pass || echo "attach v0 failed"
ip -n a link set v1 xdpdrv obj "$OBJ" program "$PROG" || echo "attach v1 failed"
ping -q -c 200 -i 0.01 -W 1 -s 8000 10.9.0.2 >/dev/null 2>&1
ping -q -c 200 -i 0.01 -W 1 -s 64 10.9.0.2 >/dev/null 2>&1
txed=$(bpftool map dump name tx.bss 2>/dev/null | grep -o '"txed": [0-9]*' | grep -o '[0-9]*$' | sort -n | tail -1)
# Tear down so page_pool destruction runs and in-flight leaks show up.
ip link del v0
ip netns del a
sleep 2
bad=$(dmesg | grep -c -E "Bad page state|page_pool leak|BUG:|WARNING:|underflow|stalled pool")
echo "RESULT $PROG: bounced=${txed:-?} kernel_errors=$bad"
dmesg | grep -E -A3 "Bad page state|BUG:|WARNING:|stalled pool" | head -20
