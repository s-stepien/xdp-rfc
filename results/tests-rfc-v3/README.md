# RFC v3 functional tests, 2026-11-16

The Testing section of

    [PATCH RFC net-next v3 0/8] xdp: reuse generic skb XDP handling for veth

## Kernels

All built with `configs/debug-v3.config` (KASAN, lockdep, DEBUG_NET,
DEBUG_VM, page_owner, KCOV; `panic_on_warn=1` on the built-in command line,
which is shortened so that vng's own arguments still fit).

| dir | tree | built as |
|---|---|---|
| base/ | net-next `7ccc5e05043b` | 7.4.0-rc2-g7ccc5e05043b |
| v3/ | base + RFC v3 1/8..8/8 | 7.4.0-rc2-gd54635083563 |
| p2only/ | base + RFC v3 1/8 + 2/8 | 7.4.0-rc2-gca9da8141993 |

The v3 and p2only kernels were built before the last review pass, which
changed only comments and commit messages: the diff to the posted patches
touches comment lines only (v3), or nothing (1/8 + 2/8).

## Tests

Run with `repro/func-v3.sh` (see its header); the BPF programs are in
`repro/`.

| test | script | what it checks |
|---|---|---|
| reproducers | `repro/all.sh` | frag shrink with xdpgeneric and veth native XDP, XDP_TX of multi-buffer and shrunk packets, a peer that trims bounced frags; no kernel errors |
| T2 | `repro/guest-t23.sh` | skbs that tc mirred redirects into veth reach its XDP program (`xdp_prog_saw` = what v1 received) |
| T3 | `repro/guest-t23.sh` | pktgen's shared skbs into a generic XDP program without frags support reach it, no drop, no warning |
| T4 | `repro/guest-t4.sh` | pktgen's shared skbs through every copy path (xdpgeneric with/without frags, veth native), 64 and 8000 B: the program sees the frame from the MAC header on, with the length pktgen sent |
| T4 trace | `repro/guest-t4-trace.sh` | T4 under bpftrace, counts which copy ran |
| veth.sh | `repro/guest-veth.sh` | tools/testing/selftests/net/veth.sh |
| test_progs | `repro/guest-selftests.sh` | `test_progs -t xdp,ns_xsk` |

`build/percommit.log`: for each commit of the series, a W=1 build of the
changed files (`net/core/{dev,skbuff,filter,xdp}.o`, `drivers/net/veth.o`)
and `checkpatch.pl --strict`; a commit line with nothing after it means no
warning. (The first three lines are an interrupted start of the same run.)

## Results

v3 (`v3/`):

```
RESULT xdpgeneric: packets_shrunk=20 kernel_errors=0
RESULT xdpdrv: packets_shrunk=20 kernel_errors=0
RESULT xdp_tx_frags: bounced=200 kernel_errors=0
RESULT xdp_tx_shrink: bounced=200 kernel_errors=0
RESULT peer: bounced=50 trimmed=50 kernel_errors=0
RESULT T2 redirected_into_veth: sent=2000 v1_rx=2011 xdp_prog_saw=2010
RESULT T3 shared_generic_nofrags: sent=2000 v1_rx=2006 xdp_prog_saw=2005 v1_rx_dropped=0
T4: 7 cases, each hdr_ok=5000 of 5000 sent, length unchanged, kernel_errors=0
T4 trace: __skb_pp_cow_data() with MAC offset 25000, skb_copy_expand() 10000
veth.sh: "xdp_tx to peer with gro on" ok; only the udpgso tests whose
         helpers are not built fail (as on base); splats=0
test_progs: 34/205 PASSED, 1 SKIPPED (1 not built), 0 FAILED, no splats
```

(`v1_rx` and `xdp_prog_saw` also count a few IPv6 neighbour packets, hence
2010/2011 for 2000 sent. T4 checks only the packets with pktgen's headers:
`hdr_ok`.)

Plain net-next (`base/`, verbose logs with the full dmesg):

- `all-base-kasan-verbose.log`: the xdpgeneric frag shrink reproducer ends
  in `BUG: Bad page state` from page_frag_free() and a panic (the series
  fixes it).
- `t23-base-kasan-verbose.log`: T3 hits
  `WARNING: net/core/skbuff.c:2385 at pskb_expand_head` (shared skb) and
  panics with panic_on_warn (2/8 fixes it).
- veth.sh and test_progs: same results as v3.

1/8 + 2/8 alone (`p2only/`): T2 2010/2010, T3 2005/2005, T4 all 5000/5000,
kernel_errors=0. The trace shows generic XDP copying shared skbs with the
new code (10000 with MAC offset, 10000 skb_copy_expand()); veth native
still uses its own copy there (offset 0) until 6/8 moves it to the generic
path.
