#!/bin/bash
# Runs in the VM as root: guest-t4.sh <this dir>
# T4: shared skbs (pktgen keeps a reference) through every copy path of
#     "net: do not modify shared skbs in generic XDP" (RFC v3 2/8); the
#     program checks it sees the frame from the MAC header on and records
#     its length:
#     xdpgeneric + frags prog   -> system page_pool copy with MAC offset
#     xdpgeneric + no-frags prog -> linear skb_copy_expand()
#     xdpdrv (veth)              -> veth page_pool copy with MAC offset
D="$1"; OBJ="$D/chk.bpf.o"; N=5000
PG=/proc/net/pktgen
ERR="Bad page state|page_pool leak|BUG:|WARNING:|underflow|stalled pool"
echo "KERNEL $(uname -r)"; dmesg -C
vals() { # <netns> <dev> -> "seen ok lens mismatches"
	local pid mid
	pid=$(ip -n "$1" -j -d link show "$2" | jq '.[0].xdp.prog.id // .[0].xdp.attached[0].prog.id')
	for m in $(bpftool -j prog show id "$pid" | jq '.map_ids[]'); do
		[ "$(bpftool -j map show id "$m" | jq -r .name)" = cnt ] && mid=$m
	done
	bpftool map dump id "$mid" | jq -r '
	  def vs(k): [.[] | select(.key == k) | .values[] | .value];
	  "seen=\(vs(0)|add) hdr_ok=\(vs(1)|add) len=\(vs(2) | map(select(. != 0)) | unique | map(tostring) | join(",")) len_changes=\(vs(3)|add)"'
}
pktgen() { # <dev> <dst mac> <size>
	for t in $PG/kpktgend_*; do echo rem_device_all > "$t"; done
	echo "add_device $1@0" > $PG/kpktgend_0
	for s in "count $N" "clone_skb 0" "pkt_size $3" "delay 0" "dst 10.9.0.2" "dst_mac $2"; do
		echo "$s" > "$PG/$1@0"; done
	echo start > $PG/pgctrl
}
rx() { ip -n "$1" -j -s link show "$2" | jq '.[0].stats64.rx.packets'; }
drop() { ip -n "$1" -j -s link show "$2" | jq '.[0].stats64.rx.dropped'; }

run() { # <mode> <prog> <size> [mtu]
	local mtu=${4:-9000}
	ip netns add y
	ip link add v0 mtu $mtu type veth peer name v1 mtu $mtu netns y
	ip link set v0 up; ip -n y link set v1 up
	ip -n y link set v1 "$1" obj "$OBJ" program "$2" || echo "attach $1 $2 failed"
	sleep 0.5
	pktgen v0 "$(ip -n y -j link show v1 | jq -r '.[0].address')" "$3"
	sleep 0.5
	echo "RESULT T4 $1 $2 $3: sent=$N v1_rx=$(rx y v1) v1_rx_dropped=$(drop y v1) $(vals y v1)"
	ip link del v0; ip netns del y; sleep 0.3
}

run xdpgeneric chk_frags 64
run xdpgeneric chk_frags 8000
run xdpgeneric chk 64
run xdpgeneric chk 8000
run xdpdrv chk_frags 64
run xdpdrv chk_frags 8000
run xdpdrv chk 64 1500

echo "kernel_errors=$(dmesg | grep -c -E "$ERR")"
dmesg | grep -E -A8 "$ERR" | head -40
