# Profiles: 64 B devmap redirect to veth and cpumap, 2026-11-17

Where do the devmap losses come from, and why is cpumap a bit faster? Same
kernels as `bench-2026-11-16-v3` (base 7ccc5e05043b, v3 built as
91ef8e809a02). `night2.sh 3` booted base and v3 in turn, 3 boots each,
pinned; `prof2.sh` (in the VM, reuses the helpers of `bench.sh`) runs six
cases, each with perf stat and perf record (flat, -g) of the named CPUs and
the packets delivered in each window:

| case | NAPI | senders | CPUs profiled |
|---|---|---|---|
| s1_devmap | softirq | 1 | 1 (everything) |
| s4_devmap | softirq | 1,3,4,5 | 1,3,4,5 (everything) |
| t2_devmap | threaded | 1,4 | 3 (v1's NAPI thread, the bottleneck) |
| s1/s4/t2_cpumap | as above | as above | 2 (cpumap kthread) |

`cmp.py <case> <base out> <v3 out>`: self and inclusive cycles per
delivered packet; `lockwho.py <out> <case>`: spinlock cycles per packet by
path (redirect = under generic_xdp_tx/veth_xdp_xmit/__dev_flush). Outputs
in `cmp-boot<N>.txt`, `lockwho-boot<N>.txt`. The perf.data files and the
kallsyms copies (~1.3 GB) are not in the repo; `bench.sh` here is a copy
of `bench/bench.sh`, which `prof2.sh` sources.
v3's boot 1 was slower in every case (as sometimes happens); boots 2 and 3
agree, numbers below are from them.

## devmap redirect to veth

Spinlock cycles per packet (boots 2/3):

| | base | v3 |
|---|---|---|
| s1: redirect path, target ring lock | 99 | 104-105 |
| s4: redirect path, target ring lock | 6 | 107-108 (no slowpath) |
| s4: pktgen into v1's ring, slowpath (4 senders) | 283 | 378-391 |
| t2: redirect path, target ring lock | 7 | 132 |
| t2: waking the target's NAPI thread (slowpath) | 0 | 28-29 |

- The redirect lock is **not contended** in v3: v1 has one queue, so one
  NAPI produces into the target's ring at a time. Its cost is taking it per
  packet: base sent the frames of one NAPI poll with one lock
  (ndo_xdp_xmit bulk), so it paid ~6 cycles/packet once polls see batches.
- With one sender every poll has one packet, so base also took the lock
  per packet (99 vs 104): that is why the one-sender loss is small.
- The contended lock is v1's own ring, which the 4 pktgen threads fill, on
  both kernels; more per packet with v3 because v1 drains it more slowly.
- t2 (v1's CPU): +259 cycles/packet; per-packet lock +125, NAPI wake-up of
  the target +40 (__napi_schedule), generic transmit (generic_xdp_tx,
  veth_xmit, features) ~+150; base's veth_xdp_get() (-137) is gone.

## cpumap

On the saturated cpumap CPU (s4, t2), boots 2/3: v3 -32 to -48 cycles per
packet (base 965-1000), matching the +3.5-4 % throughput. In all boots v3
no longer runs `__xdp_build_skb_from_frame` (-44 to -53),
`napi_skb_cache_get_bulk` (-27 to -43), `page_frag_free` (-41 to -45);
new is returning the pages to v1's page_pool (`napi_pp_put_page` +
its lock, +45 to +60). The network stack part (UDP no port, ICMP
unreachable) varies by ~+-100 cycles between boots, which is why boot 1
shows +1/+27 overall. s1: CPU 2 is not saturated, cycles per packet are
not comparable there.
