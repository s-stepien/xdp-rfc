#!/usr/bin/env python3
"""Bootstrap confidence intervals for bench.sh logs.

Usage: bench-ci.py <logs dir> <old>:<new> [<old>:<new> ...]

For every test prints the change of the median (new / old - 1) and its
95 % bootstrap confidence interval (5000 resamples). Uses the delivered
packets (DELIV lines) for TX/redirect tests and RESULT for DROP tests.
"""
import re, sys, random, statistics
from collections import defaultdict
from pathlib import Path
L=Path(sys.argv[1]); pairs=[p.split(':') for p in sys.argv[2:]]
res=defaultdict(lambda: defaultdict(list))
for n in {x for p in pairs for x in p}:
    for f in sorted(L.glob(f"bench-{n}-*.log")):
        for line in f.read_text().splitlines():
            m=re.match(r"(RESULT|DELIV) (\S+) size=(\d+) cpus=(\d+) rep=\d+ pps=(\d+)",line)
            if m and (m[1]=="DELIV" or m[2] in("native_drop","generic_drop")):
                res[(m[2],int(m[3]),int(m[4]))][n].append(int(m[5]))
random.seed(1)
def ci(a,b):
    r=[]
    for _ in range(5000):
        r.append(statistics.median(random.choices(b,k=len(b)))/statistics.median(random.choices(a,k=len(a)))-1)
    r.sort(); return r[125]*100,r[4875]*100
print(f"{'test':<26}"+"".join(f"{a+'→'+b:>28}" for a,b in pairs))
for k in sorted(res,key=lambda k:(k[1],k[0],k[2])):
    row=f"{k[0]+' '+str(k[1])+'B c'+str(k[2]):<26}"
    for a,b in pairs:
        A,B=res[k][a],res[k][b]; d=(statistics.median(B)/statistics.median(A)-1)*100; lo,hi=ci(A,B)
        row+=f"{d:>+8.1f}% [{lo:+5.1f},{hi:+5.1f}] n={len(A)}"
    print(row)
