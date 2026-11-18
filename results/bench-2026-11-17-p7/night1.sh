#!/bin/bash
# #1: does 8/8 recover the multi-sender 64 B XDP_TX loss? base vs p7 (1/8..7/8) vs v3.
set -u
# KBUILD: directory with the kernel builds nn-base, nn-p7, nn-v3
OUT=$(dirname "$(readlink -f "$0")")
B=$(readlink -f "$OUT/../..")
K=${KBUILD:?set KBUILD}
run() {
	mode=$1; shift
	mkdir -p "$OUT/$mode"
	echo "== $mode start $(date +%T)"
	env "$@" "$B/bench/bench-run.sh" 6 2 8 base="$K/nn-base" p7="$K/nn-p7" v3="$K/nn-v3" 2>&1 | tee "$OUT/$mode/run.log"
	mv "$B"/logs/* "$OUT/$mode/"
	echo "== $mode end $(date +%T)"
}
run threaded2 NAPI=threaded SENDERS=1,4
run multi NAPI=softirq SENDERS=1,3,4,5
