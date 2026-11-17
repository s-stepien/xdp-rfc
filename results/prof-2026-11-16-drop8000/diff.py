#!/usr/bin/env python3
# diff.py <base out dir> <base log> <v3 out dir> <v3 log>: per-symbol cycles/pkt (share x cycles/pkt from perf stat)
import sys, subprocess, re
def load(d, log):
    pk = int(re.search(r'\d+', open(f'{d}/pkts.txt').read())[0])
    cyc = int(re.search(r'^STAT (\d+),,cycles', open(log, errors='replace').read(), re.M)[1])
    out = subprocess.run(['perf', 'report', '-i', f'{d}/perf.data', f'--kallsyms={d}/kallsyms.txt', '--sort', 'sym',
                          '--stdio', '-F', 'overhead,sym'], capture_output=True, text=True).stdout
    r = {}
    for l in out.splitlines():
        m = re.match(r'\s+([\d.]+)%\s+\[\S\]\s+(\S+)', l)
        if m: r[m[2]] = float(m[1]) / 100 * cyc / pk
    return r, cyc / pk
b, cb = load(sys.argv[1], sys.argv[2]); v, cv = load(sys.argv[3], sys.argv[4])
print(f'cycles/pkt: base {cb:.0f}  v3 {cv:.0f}  ({cv-cb:+.0f})')
rows = sorted(set(b) | set(v), key=lambda s: -abs(v.get(s, 0) - b.get(s, 0)))
for s in rows[:22]:
    print(f'  {s:40} {b.get(s,0):7.1f} {v.get(s,0):7.1f} {v.get(s,0)-b.get(s,0):+7.1f}')
