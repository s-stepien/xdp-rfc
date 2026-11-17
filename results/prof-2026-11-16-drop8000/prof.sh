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
#
# NAPI=softirq (default): veth NAPI runs as softirq on the CPU that kicks it,
#   i.e. pktgen's CPU 1; every NAPI poll handles one packet.
# NAPI=threaded: threaded NAPI, the threads pinned away from pktgen (v1 on
#   CPU 3, v0 on CPU 5, v3 on CPU 6), so polls see batches of packets.
# SENDERS=<cpus>: pktgen threads sending into v0 (default 1). With e.g.
#   SENDERS=1,3,4,5 and softirq NAPI, the NAPI poll runs on the CPU of the
#   sender that kicked it while the others keep filling the ring, as with
#   several senders into one veth. CPU 2 is the cpumap target, keep it free.
set -u
# One output stream: stderr written separately into the same log through
# virtme-ng can overwrite stdout lines.
exec 2>&1
D="$1"; REPS="${2:-3}"; SECS="${3:-8}"
NAPI="${NAPI:-softirq}"
SENDERS="${SENDERS:-1}"
SENDERS="${SENDERS//,/ }"	# commas allowed: spaces do not survive the vng command line
case "$NAPI" in softirq|threaded) ;; *) echo "NAPI must be softirq or threaded"; exit 1 ;; esac
OBJ="$D/bench.bpf.o"
ERR="Bad page state|page_pool leak|BUG:|WARNING:|underflow|stalled pool|inflight"
PG=/proc/net/pktgen

echo "KERNEL $(uname -r) cpus=$(nproc) reps=$REPS secs=$SECS napi=$NAPI senders=${SENDERS// /,}"
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
	if [ "$NAPI" = threaded ]; then
		# only devices with an XDP program have NAPI; others fail, silently
		ip netns exec a sh -c 'echo 1 > /sys/class/net/v1/threaded' 2>/dev/null
		echo 1 > /sys/class/net/v0/threaded 2>/dev/null
		ip netns exec b sh -c 'echo 1 > /sys/class/net/v3/threaded' 2>/dev/null
		sleep 0.3
		local p
		for p in $(pgrep '^napi/v1-'); do taskset -pc 3 "$p" >/dev/null; done
		for p in $(pgrep '^napi/v0-'); do taskset -pc 5 "$p" >/dev/null; done
		for p in $(pgrep '^napi/v3-'); do taskset -pc 6 "$p" >/dev/null; done
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

# ---- nn-prof8k: veth native XDP drop, 8000 B (3 frags), softirq NAPI, one
# pktgen sender on CPU 1: veth_xmit -> veth NAPI (softirq) all run on CPU 1.
OUT=$D/out-$(uname -r | sed 's/.*-g//')
mkdir -p $OUT
echo 0 > /proc/sys/kernel/kptr_restrict; echo -1 > /proc/sys/kernel/perf_event_paranoid
cp /proc/kallsyms $OUT/kallsyms.txt
setup native xdp_drop_cnt
mac=$(ip -n a -j link show v1 | jq -r '.[0].address')
for t in $PG/kpktgend_*; do pgset "$(basename "$t")" rem_device_all; done
pgset kpktgend_1 "add_device v0@1"
for s in "count 0" "clone_skb 0" "pkt_size 8000" "frags 3" "delay 0" "dst 10.9.0.2" "dst_mac $mac"; do pgset "v0@1" "$s"; done
echo start > $PG/pgctrl &
sleep 2
c0=$(counter a v1); sleep 8; c1=$(counter a v1)
echo "PPS_PLAIN $(( (c1 - c0) / 8 ))" | tee $OUT/plain.txt
c0=$(counter a v1)
perf stat -C 1 -x, -o $OUT/stat.csv -e cycles,instructions -- sleep 4
c1=$(counter a v1)
echo "PKTS_STAT $((c1 - c0))" | tee $OUT/pkts.txt
grep -v "^#" $OUT/stat.csv | grep . | sed 's/^/STAT /'
perf record -q -C 1 -e cycles -c 20011 -o $OUT/perf.data -- sleep 4 2>/dev/null
perf record -q -g -C 1 -e cycles -c 20011 -o $OUT/perf-g.data -- sleep 4 2>/dev/null
echo stop > $PG/pgctrl; wait
teardown
echo "ERRORS $(dmesg | grep -c -E "$ERR")"
