#!/bin/bash
# guest-t4.sh under bpftrace: how many copies went through the shared path
# (__skb_pp_cow_data with a MAC offset, skb_copy_expand from generic XDP).
D="$1"
bpftrace -q -e '
kprobe:__skb_pp_cow_data /arg3 > 0/ { @pp_shared_off = count(); }
kprobe:__skb_pp_cow_data /arg3 == 0/ { @pp_nonshared = count(); }
kprobe:skb_copy_expand { @copy_expand = count(); }
' > "$D/trace.out" 2>&1 &
BT=$!; sleep 3
bash "$D/guest-t4.sh" "$D"
kill -INT $BT; wait $BT; echo "== trace"; cat "$D/trace.out"
