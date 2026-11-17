# Profile: veth native XDP_DROP at 8000 B, 2026-11-16

Why is native XDP_DROP of 8000 B (3 frags) packets 5-7 % slower with RFC
v3? Same kernels as `results/bench-2026-11-16-v3` (base 7ccc5e05043b, v3
built as 91ef8e809a02). softirq NAPI, one pktgen sender, so pktgen, veth
and the program all run on CPU 1; two pinned boots per kernel.

`prof.sh` runs in the VM like `bench/bench.sh` and records `perf record`
(flat and `-g`) of CPU 1 during the test, plus `perf stat` cycles and
instructions. `boot<N>/prof-*.log` are its outputs, `*.pin` the pinning,
`out-*/pkts.txt` the packets counted during the recording. The perf.data
files (~200 MB) are not in the repo. `diff.py` prints the per-symbol self
cycles/packet difference, `incl.py` inclusive cycles/packet per stage.

|  | boot1 | boot2 |
|---|---|---|
| base Mpps | 2.93 | 2.86 |
| v3 Mpps | 2.72 (-7 %) | 2.79 (-3 %) |
| cycles/packet base -> v3 | 1661 -> 1804 | 1738 -> 1746 |

Inclusive cycles/packet differ far more between boots than between
kernels: e.g. base `skb_copy_bits` 689 (boot1) vs 292 (boot2),
`pktgen_alloc_skb` 45 vs 183, and the page allocator's pcp
`_raw_spin_trylock` (pktgen's large head alloc/free) is 2.4 % of CPU in base
boot1 but ~10 % in the other three boots. Freeing pktgen's skb is higher
with v3 in both boots; the new generic-path code itself is small
(`__do_xdp_generic` self ~7 cycles/packet).

Conclusion: no single new hot spot; the difference sits in page allocator
and cache behaviour around the 8000 B copies, which varies from boot to
boot. Two boots are not enough to say more.
