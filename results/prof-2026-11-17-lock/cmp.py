#!/usr/bin/env python3
# cmp.py <case> <out dir A> <out dir B> [n]: per-symbol self cycles per
# delivered packet (symbol share x perf stat cycles / packets), A vs B,
# sorted by the size of the difference. Also: inclusive cycles/packet of
# a few path functions from perf-g.data.
import sys, subprocess, re
def stat(d):
    pk = int(open(f'{d}/pkts.txt').read())
    cyc = sum(int(l.split(',')[0]) for l in open(f'{d}/stat.csv')
              if ',cycles' in l and l.split(',')[0].isdigit())
    return pk, cyc
def report(d, data, extra):
    return subprocess.run(['perf', 'report', '-i', f'{d}/{data}', f'--kallsyms={d}/../kallsyms.txt',
                           '--sort', 'sym', '--stdio'] + extra, capture_output=True, text=True).stdout
def flat(d):
    pk, cyc = stat(d); r = {}
    for l in report(d, 'perf.data', ['-F', 'overhead,sym']).splitlines():
        m = re.match(r'\s+([\d.]+)%\s+\[\S\]\s+(\S+)', l)
        if m: r[m[2]] = float(m[1]) / 100 * cyc / pk
    return r, cyc / pk
WANT = ['veth_xmit', 'veth_forward_skb', '__veth_xdp_flush', '__napi_schedule', 'napi_schedule_prep',
        '_raw_spin_lock', 'queued_spin_lock_slowpath', 'generic_xdp_tx', 'dev_map_generic_redirect',
        'xdp_do_generic_redirect', '__do_xdp_generic', 'veth_poll', 'veth_xdp_rcv',
        'cpu_map_kthread_run', '__xdp_build_skb_from_frame', 'xdp_build_skb_from_frame',
        'cpu_map_bpf_prog_run', 'netif_receive_skb_list_internal', '__netif_receive_skb_list_core',
        'kmem_cache_alloc_bulk', 'napi_skb_cache_get', '__ip_rcv_finish', 'udp_rcv', 'kfree_skb_reason',
        'kfree_skb_list_reason', 'consume_skb', 'page_pool_put_unrefed_netmem', 'ptr_ring_consume_batched']
def incl(d):
    pk, cyc = stat(d); r = {}
    for l in report(d, 'perf-g.data', ['--children', '-g', 'none']).splitlines():
        m = re.match(r'\s+([\d.]+)%\s+([\d.]+)%\s+\[\S\]\s+(\S+)', l)
        if m and m[3] in WANT: r[m[3]] = float(m[1]) / 100 * cyc / pk
    return r
case, a, b = sys.argv[1:4]; n = int(sys.argv[4]) if len(sys.argv) > 4 else 20
A, ca = flat(f'{a}/{case}'); B, cb = flat(f'{b}/{case}')
pa, _ = stat(f'{a}/{case}'); pb, _ = stat(f'{b}/{case}')
print(f'{case}: cycles/pkt A {ca:.0f}  B {cb:.0f}  ({cb-ca:+.0f}); pkts in 4 s A {pa}  B {pb}')
print('  self:')
for s in sorted(set(A) | set(B), key=lambda s: -abs(B.get(s, 0) - A.get(s, 0)))[:n]:
    print(f'    {s:42} {A.get(s,0):7.1f} {B.get(s,0):7.1f} {B.get(s,0)-A.get(s,0):+7.1f}')
IA, IB = incl(f'{a}/{case}'), incl(f'{b}/{case}')
print('  inclusive:')
for s in WANT:
    if s in IA or s in IB:
        print(f'    {s:42} {IA.get(s,0):7.1f} {IB.get(s,0):7.1f} {IB.get(s,0)-IA.get(s,0):+7.1f}')
