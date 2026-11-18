#!/usr/bin/env python3
# lockwho.py <out dir> <case>: samples in queued_spin_lock_slowpath/_raw_spin_lock
# per path (as cycles per delivered packet), by the first known caller in the stack.
import sys, subprocess, collections
d = f'{sys.argv[1]}/{sys.argv[2]}'
pk = int(open(f'{d}/pkts.txt').read())
cyc = sum(int(l.split(',')[0]) for l in open(f'{d}/stat.csv') if ',cycles' in l and l.split(',')[0].isdigit())
out = subprocess.run(['perf', 'script', '-i', f'{d}/perf-g.data', f'--kallsyms={sys.argv[1]}/kallsyms.txt',
                      '-F', 'ip,sym'], capture_output=True, text=True).stdout
KEYS = ['generic_xdp_tx', 'veth_xdp_tx_skbs', 'veth_xdp_xmit', 'veth_xdp_flush_bq', '__dev_flush',
        'pktgen_xmit', 'veth_xmit', '__napi_schedule', 'veth_poll', 'page_pool', 'pktgen_alloc_skb']
tot = 0; c = collections.Counter()
for st in out.split('\n\n'):
    fr = [l.split()[1] if len(l.split()) > 1 else '' for l in st.strip().splitlines()]
    if not fr: continue
    tot += 1
    if fr[0] not in ('queued_spin_lock_slowpath', '_raw_spin_lock'): continue
    who = next((f for f in fr[1:] for k in KEYS if f.startswith(k)), fr[1] if len(fr) > 1 else '?')
    path = 'redirect' if any(f.startswith('generic_xdp_tx') or f.startswith('veth_xdp_xmit') or f.startswith('__dev_flush') for f in fr) else 'other'
    c[(fr[0], path, who)] += 1
for (s, p, w), n in c.most_common(12):
    print(f'  {s:28} {p:9} {w:28} {n / tot * cyc / pk:7.1f} cyc/pkt')
