#!/bin/bash
# veth -> devmap egress trim test, run inside the VM as root: dm.sh <dir>
#  v0 (init ns) <-> v1 (ns a): v1 redirects IPv4 through a devmap to v2
#  v2 (ns a)    <-> v3 (ns b): the devmap entry has an egress program
#                               that trims all frags; v3 accepts frames
set -u
D="$1"; T=/sys/kernel/tracing
ERR="Bad page state|page_pool leak|BUG:|WARNING:|underflow|stalled pool|inflight"
echo "KERNEL $(uname -r)"
mountpoint -q $T || mount -t tracefs none $T
cat > $T/kprobe_events <<'K'
p:cow skb_pp_cow_data
p:xret __xdp_return type=%si
K
echo 1 > $T/events/kprobes/enable; echo > $T/trace
dmesg -C
ip netns add a; ip netns add b
ip link add v0 mtu 9000 type veth peer name v1 mtu 9000 netns a
ip -n a link add v2 mtu 9000 type veth peer name v3 mtu 9000 netns b
ip addr add 10.9.0.1/24 dev v0; ip -n a addr add 10.9.0.2/24 dev v1
ip link set v0 up; ip -n a link set v1 up; ip -n a link set v2 up; ip -n b link set v3 up
ip neigh replace 10.9.0.2 lladdr "$(ip -n a -br link show v1 | awk '{print $3}')" dev v0
ip -n b link set v3 xdpdrv obj "$D/cov.bpf.o" program xdp_pass_cnt || echo "attach v3 failed"
ip netns exec a "$D/dmload" "$D/dmegress.bpf.o" v1 v2 || echo "dmload failed"
ping -q -c 20 -i 0.05 -W 1 -s 8000 10.9.0.2 >/dev/null 2>&1
ping -q -c 20 -i 0.05 -W 1 -s 56 10.9.0.2 >/dev/null 2>&1
v() { bpftool map dump name "$1" 2>/dev/null | grep -o "\"$2\": [0-9]*" | grep -o '[0-9]*$' | sort -n | tail -1; }
types=$(grep -o 'xret.*type=0x[0-9a-f]*' $T/trace | grep -o 'type=.*' | sort | uniq -c | tr -s ' \n' ' ')
echo "RESULT devmap egress: redirected=$(v dmegress.bss redirected) egress_runs=$(v dmegress.bss egress_runs) trimmed=$(v dmegress.bss trimmed) v3_frames=$(ip netns exec b bpftool map dump name cov.bss 2>/dev/null | grep -o '"passed": [0-9]*' | grep -o '[0-9]*$' | sort -n | tail -1) cow=$(grep -c ' cow:' $T/trace) types:$types errors=$(dmesg | grep -c -E "$ERR")"
echo 0 > $T/events/kprobes/enable
ip link del v0; ip -n a link del v2; ip netns del a; ip netns del b
echo "waiting 75s after teardown"; sleep 75
echo "RESULT after 75s: errors=$(dmesg | grep -c -E "$ERR")"
dmesg | grep -E -A30 "$ERR" | grep -E "BUG|dumped|kernel BUG|^\[.*\]  ?[a-z_]+\+0x" | head -30
