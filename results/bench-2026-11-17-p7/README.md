# What does 8/8 bring? base vs p7 vs v3, 2026-11-17

Checks the Performance description "8/8 recovers most of the XDP_TX loss"
with a kernel without 8/8.

| name | tree | built as |
|---|---|---|
| base | net-next `7ccc5e05043b` | 7.4.0-rc2-g7ccc5e05043b |
| p7 | base + RFC v3 1/8..7/8 | 7.4.0-rc2-g6303b8dde33b (comment-only diff to posted 7/8) |
| v3 | base + RFC v3 1/8..8/8 | 7.4.0-rc2-g91ef8e809a02 (as in bench-2026-11-16-v3) |

All three with `configs/bench.config`. `KBUILD=<builds> night1.sh` ran,
interleaved, 6 rounds x 2 runs x 8 s per kernel:

| directory | command |
|---|---|
| threaded2 | `NAPI=threaded SENDERS=1,4 bench/bench-run.sh 6 2 8 base=... p7=... v3=...` |
| multi | `NAPI=softirq SENDERS=1,3,4,5 bench/bench-run.sh 6 2 8 ...` |

36 boots, all pinned, no errors. `ci.txt`: `bench/bench-ci.py <dir>
base:p7 base:v3 p7:v3`; `summary.txt`: `bench/bench-summary.py <dir> base
p7 v3`.

## Result

64 B XDP_TX, delivered packets/s, change with 95 % CI:

| | base→p7 | base→v3 | p7→v3 (8/8) |
|---|---|---|---|
| threaded, 2 senders | -33.6 % | -3.5 % | +45.3 % [+43.9, +46.3] |
| softirq, 4 senders | -22.9 % | -13.3 % | +12.4 % [+10.4, +13.5] |

8000 B XDP_TX: 8/8 adds +22.9 % (threaded) and +3.5 % (4 senders).
devmap and cpumap redirect: no change from 8/8 (within +-1 %). XDP_DROP is
1-2 % lower with 8/8 in the threaded mode (native 64 B -2.2 % [-3.0, -1.2],
generic -1.3 %), not explained yet.

base→v3 agrees with bench-2026-11-16-v3 (threaded XDP_TX -3.5 vs -2.1 %,
devmap -38.9 vs -38.7 %; 4 senders XDP_TX -13.3 vs -13.3 %, devmap -25.4
vs -25.8 %).
