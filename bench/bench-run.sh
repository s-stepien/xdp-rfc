#!/bin/bash
# Usage: [NAPI=softirq|threaded] [SENDERS=1,3,4,5] bench-run.sh <rounds> <reps> <secs> <name>=<kernel build dir> ...
# Boots each kernel in turn (round-robin, so drift on the host hits all of
# them alike) with 8 vCPUs pinned 1:1 to host CPUs (vng-pinned.sh) and runs
# bench.sh. Logs: ../logs/bench-<name>-<round>.log, the vCPU pinning of each
# boot in ../logs/bench-<name>-<round>.log.pin. A boot whose vCPUs could not
# all be pinned is reported and its log is renamed so it is not used.
set -u
TESTS=$(dirname "$(readlink -f "$0")"); LOGS="$TESTS/../logs"
ROUNDS=$1 REPS=$2 SECS=$3; shift 3
NAPI=${NAPI:-softirq}
SENDERS=${SENDERS:-1}
mkdir -p "$LOGS"
for r in $(seq 1 "$ROUNDS"); do
	for kv in "$@"; do
		name=${kv%%=*}; dir=$(readlink -f "${kv#*=}")
		log="$LOGS/bench-$name-$r.log"
		PIN_LOG="$log.pin" timeout 1800 "$TESTS/vng-pinned.sh" "$dir" --user root --memory 8G \
			--cpus 8 --rwdir "$TESTS" -- env NAPI="$NAPI" SENDERS="$SENDERS" bash "$TESTS/bench.sh" "$TESTS" "$REPS" "$SECS" \
			> "$log" 2>&1
		rc=$?
		if ! grep -q "^PINNED 8 of 8" "$log.pin" 2>/dev/null; then
			echo "$name round $r: NOT PINNED ($(head -1 "$log.pin" 2>/dev/null)), log moved to $log.unpinned"
			mv "$log" "$log.unpinned"
			continue
		fi
		echo "$name round $r: vng exit=$rc $(grep -c '^RESULT' "$log") results, $(grep '^ERRORS' "$log")," \
		     "$(grep -o 'napi=[a-z]* senders=[0-9,]*' "$log" | head -1)"
	done
done
