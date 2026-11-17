#!/bin/bash
# Host: func-v3.sh <kernel tree> <name> <selftests/net dir> <selftests/bpf dir> [log dir]
# Runs the RFC v3 functional tests on one kernel, each in its own VM, and
# prints a summary; logs go to <log dir>/<test>-<name>.log (default: .).
#  - all.sh: frag shrink (generic/native), XDP_TX, peer bounce
#  - guest-t23.sh: T2 tc mirred into veth, T3 shared skbs, generic, no frags
#  - guest-t4.sh: T4 shared skbs through every copy path (header + length)
#  - selftests/net/veth.sh (needs lib/xdp_dummy.bpf.o built)
#  - test_progs -t xdp,ns_xsk (see README: zz-guest-selftests.sh)
# Needs: make -C repro (chk.bpf.o, cnt.bpf.o, ...), the selftests built.
set -u
R=$(dirname "$(readlink -f "$0")")
KD=$(readlink -f "$1"); N=$2; NET=$(readlink -f "$3"); BPF=$(readlink -f "$4")
L=$(readlink -f "${5:-.}")
vm() { (cd "$KD" && timeout 1800 vng -r arch/x86/boot/bzImage --user root \
	--memory 8G --cpus 8 "$@" </dev/null); }

"$R/run-in-vm.sh" "$KD" all.sh "$L/all-$N.log" >/dev/null
vm --rwdir "$R" -- bash "$R/guest-t23.sh" "$R" > "$L/t23-$N.log" 2>&1
vm --rwdir "$R" -- bash "$R/guest-t4.sh" "$R" > "$L/t4-$N.log" 2>&1
vm --rwdir "$NET" -- bash "$R/guest-veth.sh" "$NET" > "$L/veth-$N.log" 2>&1
vm --rwdir "$BPF" -- bash "$BPF/zz-guest-selftests.sh" "$BPF" -t xdp,ns_xsk \
	> "$L/test_progs-$N.log" 2>&1

echo "== $N ($(grep -a -m1 '^KERNEL' "$L/all-$N.log"))"
grep -ahE "^RESULT" "$L/all-$N.log" "$L/t23-$N.log" "$L/t4-$N.log"
grep -ahE "^kernel_errors" "$L/t23-$N.log" "$L/t4-$N.log"
grep -ah "xdp_tx to peer with gro on" "$L/veth-$N.log" | sed 's/  */ /g'
echo "veth.sh fails other than xdp_tx/udpgso: $(grep -a ' fail' "$L/veth-$N.log" |
	grep -av 'client exit code\|xdp_tx to peer\|exec of' | wc -l), $(grep -a '^splats' "$L/veth-$N.log")"
echo "test_progs: $(grep -a '^Summary' "$L/test_progs-$N.log")"
