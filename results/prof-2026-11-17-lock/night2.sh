#!/bin/bash
# Host: night2.sh <boots per kernel>. Boots base and v3 in turn, pinned, runs prof2.sh.
set -u
P=$(dirname "$(readlink -f "$0")")
# KBUILD: directory with the kernel builds nn-base and nn-v3
K=${KBUILD:?set KBUILD}
B=$(readlink -f "$P/../../bench")
for r in $(seq 1 "$1"); do
	for kv in base=nn-base v3=nn-v3; do
		n=${kv%%=*}; log=$P/prof-$n-$r.log
		PIN_LOG=$log.pin timeout 1800 "$B/vng-pinned.sh" "$K/${kv#*=}" --user root --memory 8G \
			--cpus 8 --rwdir "$P" -- env BOOT=$r bash "$P/prof2.sh" "$P" > "$log" 2>&1
		echo "$n boot $r: exit=$? $(head -1 "$log.pin") $(grep -c '^CASE' "$log") cases, $(grep '^ERRORS' "$log")"
	done
done
