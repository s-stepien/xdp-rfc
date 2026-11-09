# xdp: reuse generic skb XDP handling for veth — tests and results

Scripts, kernel configs and raw logs behind the performance numbers and
the testing section of

    [PATCH RFC net-next v2 0/4] xdp: reuse generic skb XDP handling for veth

(v1: https://lore.kernel.org/all/20260509084858.773921-1-maciej.fijalkowski@intel.com/).
Everything here can be rerun to check or extend the numbers.

```
bench/     performance benchmark (pktgen into a veth pair, XDP on the peer)
repro/     functional reproducers and helpers to run BPF selftests in a VM
configs/   bench.config (benchmark kernels), debug.config (functional tests)
results/   raw logs of every run quoted in the cover letter
```

The patches themselves are not kept here; take them from the RFC v2
posting on netdev.

## Kernels

The benchmark kernels are built from Linus' tree at `f66469d9905b`
(v7.4-rc1-537, "Merge tag 'net-7.4-rc2'") with these patches:

| name | patches on top of f66469d9905b |
|---|---|
| nvbase | [1] |
| nvrfc | [1] + RFC v2 rebased onto [1] without [2] |
| vbase | [1] + [2] |
| vrfc | [1] + [2] + RFC v2 (patches 1-4) |

- [1] Tianyi Gao, "net: fix mac_len of skbs copied by generic XDP" (patch 1/2 only):
  https://patchwork.kernel.org/patch/14941610/mbox/
  — without it, cpumap redirect of copied skbs drops every packet, on both kernels.
- [2] Vladimir Oltean, "net: pass the XDP action to generic_xdp_tx() for tracing" and
  "net: validate xmit skbs in generic_xdp_tx()": https://patchwork.kernel.org/series/1197118/mbox/

The run of 2026-11-06 calls nvbase/nvrfc `base`/`rfc`.

The functional tests ran on net-next `fa5196392691` + [1] + [2] + RFC v2
with `configs/debug.config` (KASAN, lockdep, DEBUG_NET, KCOV, page_owner).

### Benchmark config

`configs/bench.config` is virtme-ng's minimal config (`vng --kconfig`) plus
`configs/bench.fragment` (BPF, BPF JIT, XDP sockets, netns, veth, pktgen,
page_pool stats), with DEBUG_ENTRY, DEBUG_STACK_USAGE, SCHEDSTATS, DEBUG_MISC
and DEBUG_DEVRES disabled. No sanitizers, KCOV, page_owner or INIT_ON_ALLOC.
All four kernels use the identical file:

```
cp configs/bench.config <tree>/.config
make -C <tree> olddefconfig && make -C <tree> -j$(nproc)
```

## Benchmark

Requirements on the host: virtme-ng (`vng`), QEMU/KVM, clang, bpftool, jq,
ethtool, iproute2, python3.

```
make -C bench                                  # bench.bpf.o
bench/bench-run.sh 4 3 8 vbase=<tree> vrfc=<tree> ...
python3 bench/bench-summary.py logs vbase vrfc # medians, min..max, page_pool stats
python3 bench/bench-ci.py logs vbase:vrfc      # change + 95% bootstrap CI
```

`bench-run.sh <rounds> <reps> <seconds> name=tree...` boots the kernels in
turn (round-robin, so drift on the host hits all of them alike) in a VM with
8 vCPUs and 8 GB and runs `bench.sh` there; logs go to `logs/bench-<name>-<round>.log`.

`bench.sh` creates veth pair v0 (init netns) <-> v1 (netns a) with MTU 9000.
pktgen on CPU 1 sends skbs into v0 (`ndo_start_xmit`), so the XDP program on
v1 runs on veth's skb path, the path the series changes. Sizes: 64 B, and
8000 B with 3 frags. Tests:

| test | XDP on v1 | delivered = packets/s counted at |
|---|---|---|
| native_tx | native, XDP_TX | v0's XDP program |
| native_redir | native, bpf_redirect_map() to a devmap entry for v2 | v3's XDP program (veth pair v2 <-> v3) |
| cpu_redir | native, redirect to a cpumap entry for CPU 2 | UDP packets reaching the stack (UDP NoPorts) |
| native_drop | native, XDP_DROP | v1's program |
| generic_drop | xdpgeneric, XDP_DROP, 1 and 4 pktgen threads | v1's program |

pktgen holds a reference on every skb it sends, so the skbs are shared when
they reach v1 and are always copied into page_pool memory, on both kernels.

`bench/dbg-tx-cow.sh <dir> <size> <frags>` counts `skb_pp_cow_data()` calls
per packet in the XDP_TX setup with a kprobe (run it inside the VM, e.g.
`vng -r <tree>/arch/x86/boot/bzImage --user root --rwdir bench -- bash bench/dbg-tx-cow.sh $PWD/bench 8000 3`).

## Functional tests

```
make -C repro          # BPF objects and dmload (needs libbpf)
repro/run-in-vm.sh <tree> all.sh all.log   # frag shrink (generic/native), XDP_TX, peer bounce
repro/run-in-vm.sh <tree> dm.sh dm.log     # veth -> devmap egress program trimming frags
```

BPF selftests: build `tools/testing/selftests/bpf` in the tree, copy
`repro/guest-selftests.sh` to `<tree>/tools/testing/selftests/bpf/zz-guest-selftests.sh`, then

```
repro/vm-selftests.sh <tree> xdp.log -t ns_xsk,xdp
repro/vm-selftests.sh <tree> xsk.log xsk       # test_xsk.sh
```

`repro/lo-repro.sh` (see its header) runs `bpf_prog_test_run` after generic
XDP on lo.

## Results

QEMU/KVM on a desktop host (no CPU pinning). Delivered packets/s, median of
12 runs of 8 s over 4 alternating boots per kernel; Δ with 95 % bootstrap
confidence interval (`results/bench-2026-11-09`):

| test | size | vbase → vrfc (Mpps) | Δ |
|---|---|---|---|
| XDP_TX | 64 B | 4.49 → 4.04 | −10.1 % [−10.9, −8.7] |
| XDP_TX | 8000 B | 2.25 → 1.87 | −16.7 % [−17.9, −15.4] |
| REDIRECT devmap → veth | 64 B | 4.30 → 3.95 | −8.1 % [−9.5, −6.9] |
| REDIRECT devmap → veth | 8000 B | 2.18 → 1.81 | −16.7 % [−18.5, −15.1] |
| REDIRECT cpumap | 64 B | 4.49 → 4.47 | −0.4 % [−2.4, +2.6] |
| REDIRECT cpumap | 8000 B | 2.02 → 2.27 | +12.6 % (vs nvbase, see below) |
| XDP_DROP, native veth | 64 B | 5.65 → 5.42 | −3.9 % [−5.6, −2.0] |
| XDP_DROP, native veth | 8000 B | 2.82 → 2.71 | −3.7 % [−5.5, −2.8] |
| XDP_DROP, xdpgeneric | 64 B | 5.63 → 5.83 | +3.6 % [+2.1, +4.8] |
| XDP_DROP, xdpgeneric | 8000 B | 2.94 → 3.00 | +1.9 % [−1.2, +2.5] |

- nvbase → vbase (Vladimir's patches alone) is within ±2 % for every test:
  without the series no benchmark test calls generic_xdp_tx(). This also
  shows the noise floor between two builds.
- nvrfc → vrfc (cost of Vladimir's validation on the series' TX paths):
  XDP_TX −3.6 % and devmap −2.6 % at 64 B; other tests moved +1..+4 %.
- cpumap 8000 B: 3 of the 12 vbase runs stalled (the cpumap kthread
  delivered almost nothing), so nvbase is used as the base there; Vladimir's
  patches do not touch that path.
- page_pool of v1 at 8000 B: base releases ~4.8M pages/s
  (`rx_pp_recycle_released_ref`); with the series they are recycled
  (`rx_pp_recycle_ring`), 0 released.
- `skb_pp_cow_data()` copies per packet in XDP_TX: base 1 (64 B and 8000 B);
  with the series 1 at 64 B and 2 at 8000 B (the receiving veth gets an skb
  with frags instead of an xdp_frame and copies it again).

The earlier run with 15 values per kernel (`results/bench-2026-11-06`,
nvbase → nvrfc) shows the same picture before the rebase onto Vladimir's
patches: XDP_TX −5.8 % / −13.9 %, devmap −2.0 % / −13.6 %, cpumap +0.9 % /
+15.1 % (64 B / 8000 B).

Functional tests of RFC v2 (`results/tests-rfc-v2`): `test_progs -t ns_xsk,xdp`
34/205 passed, 0 failed, no kernel warnings; `test_xsk.sh` only fails
DRV XDP_ADJUST_TAIL_GROW (also with busy poll), as without the series;
all reproducers pass without kernel errors.

## License

The scripts and BPF programs are GPL-2.0.
