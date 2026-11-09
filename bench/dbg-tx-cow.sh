#!/bin/bash
# Count page_pool copies per packet in the XDP_TX test: dbg-tx-cow.sh <dir> <size> <frags>
D=$1; OBJ=$D/bench.bpf.o; PG=/proc/net/pktgen; T=/sys/kernel/tracing
mountpoint -q $T || mount -t tracefs nodev $T
ip netns add a
ip link add v0 mtu 9000 type veth peer name v1 mtu 9000 netns a
ip addr add 10.9.0.1/24 dev v0; ip -n a addr add 10.9.0.2/24 dev v1
ip link set v0 up; ip -n a link set v1 up
ip -n a link set v1 xdpdrv obj $OBJ program xdp_tx_cnt     # bounces back to v0
ip link set v0 xdpdrv obj $OBJ program xdp_drop_cnt        # receiver of the bounce
echo 'p:cow skb_pp_cow_data' >> $T/kprobe_events || { echo "no kprobe events"; exit 1; }
echo 'p:frm veth_xdp_rcv_one' >> $T/kprobe_events 2>/dev/null
echo 32768 > $T/buffer_size_kb; echo 1 > $T/events/kprobes/enable
mac=$(ip -n a -j link show v1 | jq -r '.[0].address')
for t in $PG/kpktgend_*; do echo rem_device_all > $t; done
echo "add_device v0@1" > $PG/kpktgend_1
for s in "count 10000" "clone_skb 0" "pkt_size $2" "frags $3" "delay 0" "dst 10.9.0.2" "dst_mac $mac"; do echo "$s" > $PG/v0@1; done
echo start > $PG/pgctrl; sleep 1
echo 0 > $T/events/kprobes/enable
echo "size=$2 packets=10000 copies=$(grep -c ' cow:' $T/trace) frames_at_v0=$(grep -c ' frm:' $T/trace)"
