#!/usr/bin/env python3
"""Bootstrap confidence intervals for bench.sh logs.

Usage: bench-ci.py [--per-run] [--boots] <logs dir> <old>:<new> [<old>:<new> ...]

For every test prints the change of the median (new / old - 1) and its
95 % bootstrap confidence interval (5000 resamples). Uses the delivered
packets (DELIV lines) for TX/redirect tests and RESULT for DROP tests.

Runs of the same boot are not independent (same memory layout, same host
state), so the default is a cluster bootstrap: each resample draws whole
boots (log files bench-<name>-<round>.log) with replacement, separately for
old and new, and takes the median of all runs of the drawn boots. With few
boots the interval is wide and coarse; that is the real uncertainty.
--per-run resamples single runs as if independent (the old behaviour; the
interval is too narrow when boots differ). --boots also prints the median
of every boot, which shows boots or runs that fall out of line.

Lines with RESULT/DELIV not at the start of the line (log output mixed into
another line) are not used; their number is reported.
"""
import random
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

args = sys.argv[1:]
per_run = "--per-run" in args
show_boots = "--boots" in args
args = [a for a in args if not a.startswith("--")]
if len(args) < 2:
    sys.exit(__doc__)
L = Path(args[0])
pairs = [p.split(":") for p in args[1:]]

LINE = re.compile(r"^(RESULT|DELIV) (\S+) size=(\d+) cpus=(\d+) rep=\d+ pps=(\d+)$")
# res[test][kernel][boot] = [pps, ...]
res = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
broken = defaultdict(int)
for n in {x for p in pairs for x in p}:
    for f in sorted(L.glob(f"bench-{n}-*.log")):
        boot = f.stem.rsplit("-", 1)[1]
        for line in f.read_text(errors="replace").splitlines():
            m = LINE.match(line)
            if not m:
                if re.search(r"(RESULT|DELIV) \S+ size=", line):
                    broken[n] += 1
                continue
            if m[1] == "DELIV" or m[2] in ("native_drop", "generic_drop"):
                res[(m[2], int(m[3]), int(m[4]))][n][boot].append(int(m[5]))

random.seed(1)


def runs(boots):
    return [v for b in boots.values() for v in b]


def draw(boots):
    """One bootstrap sample: whole boots drawn with replacement (or runs)."""
    if per_run:
        r = runs(boots)
        return random.choices(r, k=len(r))
    out = []
    for b in random.choices(list(boots), k=len(boots)):
        out += boots[b]
    return out


def ci(a, b):
    r = sorted(statistics.median(draw(b)) / statistics.median(draw(a)) - 1
               for _ in range(5000))
    return r[125] * 100, r[4875] * 100


mode = "single runs (as if independent)" if per_run else "whole boots (cluster bootstrap)"
print(f"95 % CI, resampling {mode}; n = boots x runs per boot")
print(f"{'test':<26}" + "".join(f"{a + '→' + b:>31}" for a, b in pairs))
for k in sorted(res, key=lambda k: (k[1], k[0], k[2])):
    row = f"{k[0] + ' ' + str(k[1]) + 'B c' + str(k[2]):<26}"
    for a, b in pairs:
        A, B = res[k][a], res[k][b]
        if not A or not B:
            row += f"{'(missing)':>31}"
            continue
        d = (statistics.median(runs(B)) / statistics.median(runs(A)) - 1) * 100
        lo, hi = ci(A, B)
        nb = f"{len(B)}x{round(len(runs(B)) / len(B))}"
        row += f"{d:>+8.1f}% [{lo:+6.1f},{hi:+6.1f}] n={nb:<4}"
    print(row)

if show_boots:
    names = sorted({x for p in pairs for x in p})
    print("\nmedian of each boot (Mpps)")
    for k in sorted(res, key=lambda k: (k[1], k[0], k[2])):
        for n in names:
            boots = res[k][n]
            vals = " ".join(f"{statistics.median(boots[b]) / 1e6:6.2f}"
                            for b in sorted(boots))
            print(f"  {k[0] + ' ' + str(k[1]) + 'B':<20} {n:<8} {vals}")

for n, c in sorted(broken.items()):
    print(f"WARNING: {n}: {c} result line(s) mixed with other output, not used")
