#!/bin/bash
# Runs all veth/generic reproducers in one VM: all.sh <dir>
D="$1"
echo "KERNEL $(uname -r)"
bash "$D/run.sh" "$D" xdpgeneric
bash "$D/run.sh" "$D" xdpdrv
bash "$D/run-tx.sh" "$D" xdp_tx_frags
bash "$D/run-tx.sh" "$D" xdp_tx_shrink
bash "$D/run-peer.sh" "$D"	# last: disables IPv6
