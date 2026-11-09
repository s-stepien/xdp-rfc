#!/usr/bin/env python3
"""Summarise bench.sh logs: bench-summary.py <logs dir> <name> <name> ...

For every test prints the median pps per kernel over all rounds and
repetitions, the min..max spread, and the change of each kernel vs the
first one. Then the page_pool stats (per second, averaged over rounds).
"""
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

logs = Path(sys.argv[1])
names = sys.argv[2:]
res = defaultdict(lambda: defaultdict(list))   # test -> kernel -> [pps]
pp = defaultdict(lambda: defaultdict(list))    # (test, stat) -> kernel -> [val]
errors = {}

for name in names:
    errors[name] = 0
    for log in sorted(logs.glob(f"bench-{name}-*.log")):
        for line in log.read_text(errors="replace").splitlines():
            m = re.match(r"(RESULT|DELIV) (\S+) size=(\d+) cpus=(\d+) rep=\d+ pps=(\d+)", line)
            if m:
                kind = "" if m[1] == "RESULT" else " deliv"
                key = f"{m[2] + kind:<19} {m[3]:>5}B cpus={m[4]}"
                res[key][name].append(int(m[5]))
                continue
            m = re.match(r"PPSTAT (\S+) size=(\d+) (\S+)=(\d+)/s", line)
            if m:
                pp[(f"{m[1]} {m[2]}B", m[3])][name].append(int(m[4]))
                continue
            m = re.match(r"ERRORS (\d+)", line)
            if m:
                errors[name] += int(m[1])

base = names[0]
hdr = f"{'test':<35}" + "".join(f"{n + ' Mpps (min..max)':>26}" for n in names) \
    + "".join(f"{'Δ ' + n:>10}" for n in names[1:])
print(hdr)
print("-" * len(hdr))
for key in sorted(res, key=lambda k: (int(re.search(r'(\d+)B ', k)[1]), k)):
    row = f"{key:<35}"
    med = {}
    for n in names:
        v = res[key].get(n, [])
        if not v:
            row += f"{'-':>26}"
            continue
        med[n] = statistics.median(v)
        row += f"{med[n] / 1e6:>10.3f} ({min(v) / 1e6:.3f}..{max(v) / 1e6:.3f})"
    for n in names[1:]:
        if base in med and n in med:
            row += f"{(med[n] / med[base] - 1) * 100:>+9.1f}%"
    print(row)

print()
print("page_pool stats of v1 (per second, mean over rounds; only first rep of each round)")
stats = sorted(pp, key=lambda k: (int(k[0].split()[1][:-1]), k))
for (test, stat) in stats:
    vals = "".join(f"{n}={statistics.mean(pp[(test, stat)][n]):>11,.0f}  " if pp[(test, stat)].get(n) else f"{n}={'-':>11}  "
                   for n in names)
    print(f"  {test:<20} {stat:<28} {vals}")

print()
print("kernel errors:", ", ".join(f"{n}={errors[n]}" for n in names))
