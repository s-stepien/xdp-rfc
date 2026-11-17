# RFC v3 benchmark, 2026-11-16

The numbers in the Performance section of

    [PATCH RFC net-next v3 0/8] xdp: reuse generic skb XDP handling for veth

## Kernels

| name | tree | built as |
|---|---|---|
| base | net-next `7ccc5e05043b` | 7.4.0-rc2-g7ccc5e05043b |
| v3 | base + RFC v3 1/8..8/8 | 7.4.0-rc2-g91ef8e809a02 |

The v3 kernel was built before the last review pass, which changed only
comments and commit messages: `git diff 91ef8e809a02 <v3 as posted>`
touches comment lines only (3 files, 7+/6-), so the compiled code is that of
the posted series. Both kernels use `configs/bench.config` unchanged.

## Method

Scripts of this repo at the commit that adds this directory (`bench/`,
including the `vng-pinned.sh` that refuses to start next to another VM).
4 rounds, kernels booted in turn, 2 runs of 8 s per test and boot, all
8 vCPUs pinned 1:1 to host CPUs 0-7 in every boot (`*.log.pin`), no log
reports errors. `run.log` of each mode is the output of `bench-run.sh`.

| directory | command |
|---|---|
| softirq | `NAPI=softirq SENDERS=1 bench/bench-run.sh 4 2 8 base=<tree> v3=<tree>` |
| multi | `NAPI=softirq SENDERS=1,3,4,5 bench/bench-run.sh 4 2 8 ...` |
| threaded2 | `NAPI=threaded SENDERS=1,4 bench/bench-run.sh 4 2 8 ...` |
| threaded | `NAPI=threaded SENDERS=1 bench/bench-run.sh 4 2 8 ...` |

pktgen runs with default settings, so it holds a reference on every skb
and the skbs reach v1 shared; both kernels copy them before the program
runs.

## Tables

- `<mode>/summary.txt`: `bench/bench-summary.py <mode> base v3` (medians,
  min..max, page_pool stats)
- `<mode>/ci.txt`: `bench/bench-ci.py <mode> base:v3` (change with 95 % CI
  from resampling whole boots; add `--boots` to also print every boot's
  median)
- `cover-table.txt`: the four modes in one table, delivered packets/s for
  XDP_TX and the redirects (as in the cover letter)

Rerun the tables from the logs:

```
for m in softirq multi threaded2 threaded; do
	python3 bench/bench-summary.py results/bench-2026-11-16-v3/$m base v3
	python3 bench/bench-ci.py results/bench-2026-11-16-v3/$m base:v3
done
```
