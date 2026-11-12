#!/bin/bash
# Run virtme-ng with the VM's vCPU threads pinned 1:1 to host CPUs, so that
# results do not depend on where the host scheduler puts the vCPUs. On hosts
# with several CCDs/L3 domains (e.g. Ryzen 9 9950X: CPUs 0-7 and 8-15, SMT
# siblings 16-31) unpinned vCPUs gave boots ~40 % apart in the threaded test.
#
# Usage: vng-pinned.sh <kernel build dir> <vng arguments after "-r bzImage">
# Environment:
#   PIN_CPUS   host CPUs for vCPU 0..n-1 (default "0 1 2 3 4 5 6 7": CCD 0,
#              one per physical core); other QEMU threads go to PIN_OTHER
#   PIN_OTHER  host CPUs for the remaining QEMU threads (default 8-15)
#   PIN_LOG    file for the pinning report (default: stderr)
# Only one VM may run at a time: the newest qemu-system-x86 process is pinned.
set -u
dir=$1; shift
PIN_CPUS=(${PIN_CPUS:-0 1 2 3 4 5 6 7})
PIN_OTHER=${PIN_OTHER:-8-15}
PIN_LOG=${PIN_LOG:-/dev/stderr}
cd "$dir" || exit 1
vng -r arch/x86/boot/bzImage "$@" </dev/null &
VNG=$!

qpid=
for i in $(seq 400); do
	qpid=$(pgrep -n -x qemu-system-x86 2>/dev/null)	# comm is cut to 15 chars
	[ -n "$qpid" ] && break
	sleep 0.05
done
if [ -z "$qpid" ]; then
	echo "PINNED 0: qemu not found" > "$PIN_LOG"
	kill $VNG 2>/dev/null; wait $VNG; exit 1
fi

pinned=0
for i in $(seq 200); do
	pinned=0
	for t in /proc/$qpid/task/*; do
		comm=$(cat "$t/comm" 2>/dev/null) || continue
		tid=${t##*/}
		if [[ $comm =~ ^CPU\ ([0-9]+)/KVM$ ]]; then
			n=${BASH_REMATCH[1]}
			[ "$n" -lt "${#PIN_CPUS[@]}" ] || continue
			taskset -pc "${PIN_CPUS[$n]}" "$tid" >/dev/null && pinned=$((pinned + 1))
		else
			taskset -pc "$PIN_OTHER" "$tid" >/dev/null 2>&1
		fi
	done
	[ "$pinned" -ge "${#PIN_CPUS[@]}" ] && break
	sleep 0.05
done

{
	echo "PINNED $pinned of ${#PIN_CPUS[@]} vCPUs, qemu $qpid"
	for t in /proc/$qpid/task/*; do
		comm=$(cat "$t/comm" 2>/dev/null) || continue
		[[ $comm == CPU* ]] && echo "  $comm -> host $(taskset -pc "${t##*/}" | sed 's/.*: //')"
	done
} > "$PIN_LOG"
if [ "$pinned" -lt "${#PIN_CPUS[@]}" ]; then
	kill $VNG 2>/dev/null; wait $VNG; exit 1
fi
wait $VNG
