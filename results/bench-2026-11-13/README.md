# Reference benchmark results, 2026-11-13

(Copy of the logs and tables. The kernel images, System.map files and the
write-protected originals with SHA256SUMS are kept outside the repo, in
~/work/xdp-rfc-veth/final-bench on the measuring machine; the kernel
configs are identical to configs/bench.config.)

Baseline for later comparisons (RFC v3, fixes, other experiments). Do not
change: logs, tables and kernels are write-protected, SHA256SUMS lists
every file.

## Kernels (kernels/<name>/: arch/x86/boot/bzImage, .config, System.map, kernel.release)

All from Linus' tree `f66469d9905b` + Tianyi's mac_len fix + Vladimir's two
generic_xdp_tx() patches, built with the identical `configs/bench.config`
of the xdp-rfc repo (no debug, no sanitizers).

| name | commit | content | source |
|---|---|---|---|
| base | aa3cd77b265f | base | kbuild/bench4-vbase |
| rfc  | bf4407052bb1 | + RFC v2 1/4..4/4 (code identical to the posted v2) | kbuild/bench4-vrfc |
| v1   | f8286cf0d241 | + experiment V1: XDP_TX skbs per NAPI poll as a list, generic_xdp_tx_list() with xmit_more | kbuild/xm-v1 |
| v2   | 2f0f42d85ddc | + experiment V2: veth_xmit() kicks the peer NAPI once per xmit_more burst | kbuild/xm-v2 |

patches/: RFC v2 as applied on base (rfc-v2-on-vbase.diff), V1 and V2
(0001, 0002; branches rfc-xmitmore and rfc-xmitmore-v2 in ~/work/linux).

## Method (all runs)

xdp-rfc repo bench scripts (softirq/threaded: commit 16c86cb, multi and
multi-v2: commit 2cc0319, same bench.sh except the SENDERS option), copied
into each run directory (`<run>/bench/`):

- QEMU/KVM via virtme-ng, 8 vCPUs pinned 1:1 to host CPUs 0-7 (CCD 0 of
  the Ryzen 9 9950X; other QEMU threads on 8-15), 8 GB; pinning of each
  boot in `logs/*.log.pin`
- 4 rounds, kernels booted in turn; per boot every test 3 x 8 s
- 64 B and 8000 B (3 frags) packets from pktgen into v0, XDP on v1
- tables: medians of all 12 values per kernel and test (table.py);
  CIs: bench-ci.py --boots (cluster bootstrap over boots)

| run dir | mode | senders | kernels |
|---|---|---|---|
| softirq/  | NAPI=softirq (default)  | 1 (CPU 1)        | base, rfc, v1 |
| threaded/ | NAPI=threaded, NAPI threads v1->CPU3, v0->CPU5, v3->CPU6 | 1 | base, rfc, v1 |
| multi/    | NAPI=softirq | 4 (CPUs 1,3,4,5) | base, rfc, v1 |
| multi-v2/ | NAPI=softirq | 4 (CPUs 1,3,4,5) | base, rfc, v2 |

All 48 boots: pinned 8/8, all results, 0 kernel errors.

## Results (tables.txt has all 12 tables)

base -> rfc, 64 B / 8000 B:

| | softirq, 1 sender | softirq, 4 senders | threaded |
|---|---|---|---|
| XDP_TX        | -13 / -17 % | -27 / -14 % (rerun -28 / -15) | +7 / +34 % |
| devmap -> veth | -9 / -14 %  | -25 / -12 % (rerun -25 / -13) | +1 / +37 % |
| cpumap        | -1 / +14 %  | +6 / +47 %  | +9 / +50 % |
| native drop   | -8 / -4 %   | -4 / -4 %   | +2 / -3 %  |
| generic drop  | +4 / +4 %   | +3 / +3 %   | +6 / +3 %  |

rfc -> v1: only threaded XDP_TX 64 B +10 %; 4 senders XDP_TX -6 % / -3 %;
otherwise within noise. rfc -> v2 (4 senders): XDP_TX -1.5 % / 0 %.
Noise between separately built kernels: up to ~6 % on single tests (e.g.
generic drop, which V1/V2 do not touch).

Notes: with 1 sender every NAPI poll handles 1 packet (no batching on any
kernel); with 4 senders every poll handles 64 and base's XDP_TX bulk path
sends n=16 per veth_xdp_xmit(); threaded polls see ~10-15. Short (2 s) runs
come out faster than these 8 s runs; compare only like with like.

## Comparing a new kernel against this baseline

Run the same scripts in a new directory with the new kernel *and* base/rfc
again (round-robin), e.g. for the 4-sender case:

    cp -rp ~/work/xdp-rfc/bench <new>/ && make -C <new>/bench
    cd <new> && NAPI=softirq SENDERS=1,3,4,5 bench/bench-run.sh 4 3 8 \
        base=<...>/kernels/base rfc=<...>/kernels/rfc new=<build dir>

(the archived kernels/<name>/ dirs can be passed to bench-run.sh directly;
checked: kernels/rfc boots.) Compare against this run's numbers only
for the same mode; session-to-session drift is ~2-3 %, so new-vs-rfc from
the same session is the reliable comparison.
