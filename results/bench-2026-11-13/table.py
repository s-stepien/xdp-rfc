#!/usr/bin/env python3
"""Build the RFC v2 cover letter table from bench.sh logs.

Usage: table.py [--cpus N] <logs dir> <old> <new>
--cpus: number of pktgen senders of the rows to use (default 1)
Medians over all boots and runs. XDP_TX/REDIRECT rows use the delivered
packets (DELIV), DROP rows the packets seen by v1's program (RESULT);
xdpgeneric is the 1-thread case.
"""
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

args = sys.argv[1:]
CPUS = 1
if args[:1] == ["--cpus"]:
    CPUS, args = int(args[1]), args[2:]
logs, old, new = Path(args[0]), args[1], args[2]
LINE = re.compile(r"^(RESULT|DELIV) (\S+) size=(\d+) cpus=(\d+) rep=\d+ pps=(\d+)$")
val = defaultdict(list)            # (kernel, kind, test, size, cpus) -> [pps]
for k in (old, new):
    files = sorted(logs.glob(f"bench-{k}-*.log"))
    if not files:
        sys.exit(f"no logs for {k}")
    for f in files:
        for line in f.read_text(errors="replace").splitlines():
            m = LINE.match(line)
            if m:
                val[(k, m[1], m[2], int(m[3]), int(m[4]))].append(int(m[5]))

ROWS = [("XDP_TX", "DELIV", "native_tx"),
        ("REDIRECT devmap -> veth", "DELIV", "native_redir"),
        ("REDIRECT cpumap", "DELIV", "cpu_redir"),
        ("XDP_DROP (native veth)", "RESULT", "native_drop"),
        ("XDP_DROP (xdpgeneric)", "RESULT", "generic_drop")]


def cell(kind, test, size, unit):
    a = val.get((old, kind, test, size, CPUS))
    b = val.get((new, kind, test, size, CPUS))
    if not a or not b:
        return "not measured"
    ma, mb = statistics.median(a) / 1e6, statistics.median(b) / 1e6
    return f"{ma:.2f} -> {mb:.2f}{unit} ({(mb / ma - 1) * 100:+.0f}%)".replace("(+0%)", "(0%)") \
        .replace("(-0%)", "(0%)")


print(f"{'':30}{'64 B':<26}8000 B (3 frags)")
for i, (name, kind, test) in enumerate(ROWS):
    print(f"  {name:<28}{cell(kind, test, 64, ' Mpps' if i == 0 else ''):<26}"
          f"{cell(kind, test, 8000, '')}")
