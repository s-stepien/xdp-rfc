#!/bin/bash
# lo rxq mem type leak: test_run reuses lo's rx queue 0 xdp_rxq
# Copy to <tree>/tools/testing/selftests/bpf/zz-lo-repro.sh together with
# repro/bench.bpf.o as zz-bench.bpf.o, boot with vng -v and pass the selftests
# dir. Fails (WARN in page_pool_unref_netmem() in step 3) if generic XDP
# leaves a page_pool mem type in the rxq that test_run reuses.
cd "$1" || exit 1
mountpoint -q /sys/fs/bpf || mount -t bpf bpffs /sys/fs/bpf
E="Bad page state|page_pool leak|BUG:|WARNING:|underflow"
splats() { dmesg | grep -v "Spectre V2" | grep -E -c "$E"; }
ip link set lo up
echo "== step 1: xdp_adjust_tail on a fresh boot"
./test_progs -t xdp_adjust_tail | grep -E '^Summary|FAIL'
echo "splats=$(splats)"
echo "== step 2: generic XDP on lo for one ping, then detach"
ip link set lo xdpgeneric obj ./zz-bench.bpf.o program xdp_drop_cnt || echo attach failed
ping -c1 -W1 127.0.0.1 >/dev/null
ip link set lo xdpgeneric off
echo "== step 3: xdp_adjust_tail again"
./test_progs -t xdp_adjust_tail | grep -E '^Summary|FAIL'
echo "splats=$(splats)"
dmesg | grep -v "Spectre V2" | grep -E -A3 "$E" | head -12
