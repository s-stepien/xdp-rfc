#!/usr/bin/env python3
# incl.py <out dir> <log>: inclusive (children) cycles/pkt of the main parts of the path
import sys, subprocess, re
d, log = sys.argv[1], sys.argv[2]
pk = int(re.search(r'\d+', open(f'{d}/pkts.txt').read())[0])
cyc = int(re.search(r'^STAT (\d+),,cycles', open(log, errors='replace').read(), re.M)[1])
out = subprocess.run(['perf', 'report', '-i', f'{d}/perf-g.data', f'--kallsyms={d}/kallsyms.txt', '--children',
                      '--sort', 'sym', '--stdio', '-g', 'none'], capture_output=True, text=True).stdout
want = ['pktgen_thread_worker', 'pktgen_alloc_skb', 'pktgen_finalize_skb', 'veth_xmit', 'net_rx_action', 'veth_poll',
        'veth_xdp_rcv_skb', '__do_xdp_generic', 'netif_receive_generic_xdp', 'skb_pp_cow_data', '__skb_pp_cow_data',
        'veth_convert_skb_to_xdp_buff', 'bpf_prog_run_generic_xdp', '__bpf_prog_run_generic_xdp',
        'xdp_return_buff', 'kfree_skb_reason', 'sk_skb_reason_drop', 'consume_skb', 'napi_build_skb', 'skb_copy_bits']
r = {}
for l in out.splitlines():
    m = re.match(r'\s+([\d.]+)%\s+([\d.]+)%\s+\[\S\]\s+(\S+)', l)
    if m and m[3] in want: r[m[3]] = float(m[1]) / 100 * cyc / pk
print(f'{cyc/pk:.0f} cyc/pkt total; ' + '; '.join(f'{k} {r[k]:.0f}' for k in want if k in r))
