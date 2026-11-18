#!/bin/bash
# In the VM, as root: [BOOT=<n>] prof2.sh <dir with bench.sh and bench.bpf.o>
# Profiles 64 B devmap redirect to veth and cpumap redirect (claims #2, #3):
# for each case, delivered packets/s, then perf stat (cycles, instructions)
# and perf record (flat and -g) of the CPUs named in the case, with the
# packets delivered during each window, into out-<hash>-<boot>/<case>/.
D=$1
# bench.sh up to its test loop: helpers setup/teardown/counter/pgset...
source <(sed '/^for size in/,$d' "$D/bench.sh")
OUT=$D/out-$(uname -r | sed 's/.*-g//')-${BOOT:-1}
mkdir -p "$OUT"
echo 0 > /proc/sys/kernel/kptr_restrict; echo -1 > /proc/sys/kernel/perf_event_paranoid
cp /proc/kallsyms "$OUT/kallsyms.txt"

pg_start() { # <size> <cpu list>
	local mac c s
	mac=$(ip -n a -j link show v1 | jq -r '.[0].address')
	for t in $PG/kpktgend_*; do pgset "$(basename "$t")" rem_device_all; done
	for c in $2; do
		pgset "kpktgend_$c" "add_device v0@$c"
		for s in "count 0" "clone_skb 0" "pkt_size $1" "frags 0" "delay 0" \
			 "dst 10.9.0.2" "dst_mac $mac"; do pgset "v0@$c" "$s"; done
	done
	echo start > $PG/pgctrl &
}

# <case> <napi> <senders> <prog on v1> <perf cpus> <sample period>
pcase() {
	local name=$1 senders=$3 prog=$4 cpus=$5 per=$6 o d0 d1 c0 c1
	NAPI=$2
	o=$OUT/$name; mkdir -p "$o"
	setup native "$prog"
	pg_start 64 "$senders"
	sleep 2
	c0=$(counter a v1); d0=$($DLV); sleep 8; c1=$(counter a v1); d1=$($DLV)
	echo "CASE $name napi=$NAPI senders=${senders// /,} cpus=$cpus v1_pps=$(( (c1 - c0) / 8 )) deliv_pps=$(( (d1 - d0) / 8 ))"
	d0=$($DLV)
	perf stat -C "$cpus" -x, -o "$o/stat.csv" -e cycles,instructions -- sleep 4
	d1=$($DLV)
	echo "$((d1 - d0))" > "$o/pkts.txt"
	echo "STAT $name pkts=$((d1 - d0)) $(grep -v '^#' "$o/stat.csv" | grep . | cut -d, -f1,3 | tr '\n' ' ')"
	perf record -q -C "$cpus" -e cycles -c "$per" -o "$o/perf.data" -- sleep 4 2>/dev/null
	perf record -q -g -C "$cpus" -e cycles -c "$per" -o "$o/perf-g.data" -- sleep 3 2>/dev/null
	echo stop > $PG/pgctrl; wait
	teardown
}

pcase s1_devmap  softirq  "1"       xdp_redir_cnt 1       20011
pcase s4_devmap  softirq  "1 3 4 5" xdp_redir_cnt 1,3,4,5 50021
pcase s1_cpumap  softirq  "1"       xdp_cpu_cnt   2       20011
pcase s4_cpumap  softirq  "1 3 4 5" xdp_cpu_cnt   2       20011
pcase t2_devmap  threaded "1 4"     xdp_redir_cnt 3       20011
pcase t2_cpumap  threaded "1 4"     xdp_cpu_cnt   2       20011
echo "ERRORS $(dmesg | grep -c -E "$ERR")"
dmesg | grep -E -A20 "$ERR" | head -40
