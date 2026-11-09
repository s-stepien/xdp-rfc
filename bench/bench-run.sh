#!/bin/bash
# Usage: bench-run.sh <rounds> <reps> <secs> <name>=<kernel build dir> ...
# Boots each kernel in turn (round-robin, so drift on the host hits all of
# them alike) with 8 vCPUs and runs bench.sh. Logs: ../logs/bench-<name>-<round>.log
set -u
TESTS=$(dirname "$(readlink -f "$0")"); LOGS="$TESTS/../logs"
ROUNDS=$1 REPS=$2 SECS=$3; shift 3
for r in $(seq 1 "$ROUNDS"); do
	for kv in "$@"; do
		name=${kv%%=*}; dir=$(readlink -f "${kv#*=}")
		log="$LOGS/bench-$name-$r.log"
		( cd "$dir" && timeout 1800 vng -r arch/x86/boot/bzImage --user root --memory 8G --cpus 8 \
			--rwdir "$TESTS" -- bash "$TESTS/bench.sh" "$TESTS" "$REPS" "$SECS" </dev/null > "$log" 2>&1 )
		echo "$name round $r: vng exit=$? $(grep -c '^RESULT' "$log") results, $(grep '^ERRORS' "$log")"
	done
done
