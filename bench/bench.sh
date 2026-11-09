#!/bin/bash
# XDP throughput benchmark, run inside the VM as root:
#   bench.sh <dir with bench.bpf.o> [reps] [seconds]
# pktgen sends skbs out of v0 (ndo_start_xmit = veth_xmit), so v1 sees the
# veth skb path. Every test prints one line per repetition:
#   RESULT <test> size=<bytes> cpus=<n> rep=<i> pps=<packets/s seen by v1's program>
#   DELIV  <test> ... pps=<packets/s that arrived where XDP sent them>
# and page_pool stats deltas of v1's queue (veth rq->page_pool) as PPSTAT.
# DELIV: native_tx = v0's program, native_redir = v3's program (devmap to
# another veth), cpu_redir = UDP packets reaching the stack on CPU 2
# (cpumap; pktgen sends to UDP port 9, so they count as Udp NoPorts).
set -u
D="$1"; REPS="${2:-3}"; SECS="${3:-8}"
OBJ="$D/bench.bpf.o"
ERR="Bad page state|page_pool leak|BUG:|WARNING:|underflow|stalled pool|inflight"
PG=/proc/net/pktgen

echo "KERNEL $(uname -r) cpus=$(nproc) reps=$REPS secs=$SECS"
dmesg -C

pgset() { echo "$2" > "$PG/$1" || echo "pktgen: '$2' -> $1 failed"; }

# Sum a per-CPU counter map of the program attached to <dev> in netns <ns>
# ("-" = the initial netns).
ipn() { if [ "$1" = - ]; then shift; ip "$@"; else local n=$1; shift; ip -n "$n" "$@"; fi; }
counter() { # <ns> <dev>
	local pid mid
	pid=$(ipn "$1" -j -d link show "$2" | jq '.[0].xdp.prog.id // .[0].xdp.attached[0].prog.id')
	mid=$(for m in $(bpftool -j prog show id "$pid" | jq '.map_ids[]'); do
		[ "$(bpftool -j map show id "$m" | jq -r .name)" = cnt ] && echo "$m"; done)
	bpftool -j map dump id "$mid" | jq '[.[0] | (.formatted.values // .values)[] | .value] | add'
}

map_of() { # <ns> <dev> <map name> -> id of that map of the program on <dev>
	local pid
	pid=$(ipn "$1" -j -d link show "$2" | jq '.[0].xdp.prog.id // .[0].xdp.attached[0].prog.id')
	for m in $(bpftool -j prog show id "$pid" | jq '.map_ids[]'); do
		[ "$(bpftool -j map show id "$m" | jq -r .name)" = "$3" ] && echo "$m"; done
}

udp_noports() { ip netns exec a awk '/^Udp:/ { if (h) { print $3; exit } h = 1 }' /proc/net/snmp; }

ppstats() { ip netns exec a ethtool -S v1 2>/dev/null | grep -E '^ +(rx_pp_|xdp_)' | tr -d ' ' ; }

setup() { # <mode: native|generic> <prog on v1> [peer prog on v0]
	ip netns add a
	ip link add v0 mtu 9000 type veth peer name v1 mtu 9000 netns a
	ip addr add 10.9.0.1/24 dev v0
	ip -n a addr add 10.9.0.2/24 dev v1
	ip link set v0 up; ip -n a link set v1 up
	if [ "$1" = native ]; then
		ip -n a link set v1 xdpdrv obj "$OBJ" program "$2" || echo "attach v1 $2 failed"
	else
		ip -n a link set v1 xdpgeneric obj "$OBJ" program "$2" || echo "attach v1 generic $2 failed"
	fi
	[ -n "${3:-}" ] && { ip link set v0 xdpdrv obj "$OBJ" program "$3" || echo "attach v0 $3 failed"; }
	if [ "$2" = xdp_redir_cnt ]; then
		ip netns add b
		ip -n a link add v2 mtu 9000 type veth peer name v3 mtu 9000 netns b
		ip -n a link set v2 up; ip -n b link set v3 up
		ip -n b link set v3 xdpdrv obj "$OBJ" program xdp_drop_cnt || echo "attach v3 failed"
		local idx m
		idx=$(ip -n a -j link show v2 | jq '.[0].ifindex')
		m=$(map_of a v1 dm)
		# devmap resolves the ifindex in the caller's netns: run in "a"
		ip netns exec a bpftool map update id "$m" key 0 0 0 0 \
			value $(printf '%d %d %d %d' $((idx & 255)) $((idx >> 8 & 255)) 0 0) \
			|| echo "devmap update failed"
	fi
	DLV=
	case "$2" in
	xdp_tx_cnt)    DLV="counter - v0" ;;
	xdp_redir_cnt) DLV="counter b v3" ;;
	xdp_cpu_cnt)
		# CPU 2, qsize 2048, no cpumap program
		bpftool map update id "$(map_of a v1 cm)" key 2 0 0 0 value 0 8 0 0 0 0 0 0 \
			|| echo "cpumap update failed"
		DLV=udp_noports ;;
	esac
	sleep 0.5
}

teardown() { ip link del v0 2>/dev/null; ip netns del a 2>/dev/null; ip netns del b 2>/dev/null; sleep 0.3; }

# <test> <size> <frags> <cpu list>
run() {
	local test=$1 size=$2 frags=$3 cpus=$4 mac c n
	mac=$(ip -n a -j link show v1 | jq -r '.[0].address')
	for t in $PG/kpktgend_*; do pgset "$(basename "$t")" rem_device_all; done
	n=0
	for c in $cpus; do
		pgset "kpktgend_$c" "add_device v0@$c"
		for s in "count 0" "clone_skb 0" "pkt_size $size" "frags $frags" "delay 0" \
			 "dst 10.9.0.2" "dst_mac $mac"; do
			pgset "v0@$c" "$s"
		done
		n=$((n + 1))
	done
	for r in $(seq 1 "$REPS"); do
		echo start > $PG/pgctrl &
		sleep 1
		local p0 p1 c0 c1 d0=0 d1=0
		p0=$(ppstats); c0=$(counter a v1); [ -n "$DLV" ] && d0=$($DLV)
		sleep "$SECS"
		c1=$(counter a v1); [ -n "$DLV" ] && d1=$($DLV); p1=$(ppstats)
		echo stop > $PG/pgctrl; wait
		echo "RESULT $test size=$size cpus=$n rep=$r pps=$(( (c1 - c0) / SECS ))"
		[ -n "$DLV" ] && echo "DELIV $test size=$size cpus=$n rep=$r pps=$(( (d1 - d0) / SECS ))"
		if [ "$r" = 1 ]; then
			# per-second deltas of v1's page_pool and XDP counters
			join -t: <(echo "$p0" | sort) <(echo "$p1" | sort) | \
				awk -F: -v t="$test" -v s="$size" -v S="$SECS" \
				'{d=($3-$2)/S; if (d!=0) printf "PPSTAT %s size=%s %s=%.0f/s\n", t, s, $1, d}'
		fi
	done
}

for size in 64 8000; do
	frags=0; [ "$size" = 8000 ] && frags=3

	setup native xdp_drop_cnt;            run native_drop  $size $frags 1; teardown
	setup native xdp_tx_cnt xdp_drop_cnt; run native_tx    $size $frags 1; teardown
	setup native xdp_redir_cnt;           run native_redir $size $frags 1; teardown
	setup native xdp_cpu_cnt;             run cpu_redir    $size $frags 1; teardown

	setup generic xdp_drop_cnt;           run generic_drop $size $frags 1;         teardown
	setup generic xdp_drop_cnt;           run generic_drop $size $frags "1 2 3 4"; teardown
done

echo "ERRORS $(dmesg | grep -c -E "$ERR")"
dmesg | grep -E -A20 "$ERR" | head -40
