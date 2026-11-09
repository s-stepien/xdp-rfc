#!/bin/bash
# Run inside the test VM as root: ./run-peer.sh <dir>
set -u
OBJ="$1/peer.bpf.o"
dmesg -C
echo "KERNEL $(uname -r)"
sysctl -qw net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
ip netns add a
ip netns exec a sysctl -qw net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
ip link add v0 mtu 9000 type veth peer name v1 mtu 9000 netns a
ip addr add 10.9.0.1/24 dev v0
ip -n a addr add 10.9.0.2/24 dev v1
ip link set v0 up
ip -n a link set v1 up
ip neigh add 10.9.0.2 lladdr "$(ip -n a -br link show v1 | awk '{print $3}')" dev v0
ip link set v0 xdpdrv obj "$OBJ" program xdp_trim_drop || echo "attach v0 failed"
ip -n a link set v1 xdpdrv obj "$OBJ" program xdp_bounce || echo "attach v1 failed"
ping -q -c 50 -i 0.02 -W 1 -s 8000 10.9.0.2 >/dev/null 2>&1
dump() { bpftool map dump name peer.bss 2>/dev/null | grep -o "\"$1\": [0-9]*" | grep -o '[0-9]*$' | sort -n | tail -1; }
b=$(ip netns exec a bash -c "bpftool map dump name peer.bss" 2>/dev/null | grep -o '"bounced": [0-9]*' | grep -o '[0-9]*$' | sort -n | tail -1)
t=$(dump trimmed)
ip link del v0
ip netns del a
sleep 2
bad=$(dmesg | grep -c -E "Bad page state|page_pool leak|BUG:|WARNING:|underflow|stalled pool")
echo "RESULT peer: bounced=${b:-?} trimmed=${t:-?} kernel_errors=$bad"
dmesg | grep -E -A30 "page_pool leak" | grep -E "dumped|veth_|__xdp_return|bpf_xdp_adjust_tail|page_frag_free" | head -12
