#!/bin/bash
# Runs in the VM as root: guest-t23.sh <this dir>
# T2: skbs that tc mirred redirected into a veth must run its XDP program
#     (Sashiko: veth native XDP skipped for skb->redirected).
# T3: shared skbs (pktgen keeps a reference) on generic XDP with a program
#     without frags support must reach the program, not be dropped.
D="$1"; OBJ="$D/cnt.bpf.o"; N=2000
PG=/proc/net/pktgen
ERR="Bad page state|page_pool leak|BUG:|WARNING:|underflow|stalled pool"
echo "KERNEL $(uname -r)"; dmesg -C
cnt() { # <netns> <dev>
	local pid mid
	pid=$(ip -n "$1" -j -d link show "$2" | jq '.[0].xdp.prog.id // .[0].xdp.attached[0].prog.id')
	mid=$(bpftool -j prog show id "$pid" | jq '.map_ids[0]')
	bpftool -j map dump id "$mid" | jq '[.[0] | (.formatted.values // .values)[] | .value] | add'
}
pktgen() { # <dev> <dst mac>
	for t in $PG/kpktgend_*; do echo rem_device_all > "$t"; done
	echo "add_device $1@0" > $PG/kpktgend_0
	for s in "count $N" "clone_skb 0" "pkt_size 64" "delay 0" "dst 10.9.0.2" "dst_mac $2"; do
		echo "$s" > "$PG/$1@0"; done
	echo start > $PG/pgctrl
}
rx() { ip -n "$1" -j -s link show "$2" | jq '.[0].stats64.rx.packets'; }

# ---- T2: pktgen -> p0 | p1 (ns x, tc ingress mirred -> egress v0) | v0 -> v1 (ns y, XDP)
modprobe -q act_mirred 2>/dev/null; modprobe -q cls_matchall 2>/dev/null
ip netns add x; ip netns add y
ip link add p0 type veth peer name p1 netns x
ip -n x link add v0 type veth peer name v1 netns y
ip link set p0 up; ip -n x link set p1 up; ip -n x link set v0 up; ip -n y link set v1 up
ip -n y link set v1 xdpdrv obj "$OBJ" program pass_cnt_frags || echo "attach v1 failed"
ip netns exec x tc qdisc add dev p1 clsact
ip netns exec x tc filter add dev p1 ingress matchall action mirred egress redirect dev v0 || echo "tc failed"
sleep 0.5
pktgen p0 "$(ip -n x -j link show p1 | jq -r '.[0].address')"
sleep 0.5
echo "RESULT T2 redirected_into_veth: sent=$N v1_rx=$(rx y v1) xdp_prog_saw=$(cnt y v1)"
ip link del p0; ip netns del x; ip netns del y; sleep 0.3

# ---- T3: pktgen -> v0 -> v1 (ns y), generic XDP without frags support on v1
ip netns add y
ip link add v0 type veth peer name v1 netns y
ip link set v0 up; ip -n y link set v1 up
ip -n y link set v1 xdpgeneric obj "$OBJ" program pass_cnt || echo "attach generic failed"
sleep 0.5
pktgen v0 "$(ip -n y -j link show v1 | jq -r '.[0].address')"
sleep 0.5
echo "RESULT T3 shared_generic_nofrags: sent=$N v1_rx=$(rx y v1) xdp_prog_saw=$(cnt y v1) v1_rx_dropped=$(ip -n y -j -s link show v1 | jq '.[0].stats64.rx.dropped')"
ip link del v0; ip netns del y

echo "kernel_errors=$(dmesg | grep -c -E "$ERR")"
dmesg | grep -E -A8 "$ERR" | head -30
