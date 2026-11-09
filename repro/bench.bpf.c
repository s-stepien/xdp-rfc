// SPDX-License-Identifier: GPL-2.0
/* Benchmark programs: every program counts the packets it sees in a
 * per-CPU array (no shared cache line between CPUs) and then returns a
 * fixed action. All are xdp.frags so multi-buffer packets are accepted.
 */
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u64);
} cnt SEC(".maps");

/* Slot 0 holds the target ifindex, filled in by bench.sh with bpftool. */
struct {
	__uint(type, BPF_MAP_TYPE_DEVMAP);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u32);
} dm SEC(".maps");

/* Slot 2 (CPU 2) is filled in by bench.sh: qsize, no cpumap program. */
struct {
	__uint(type, BPF_MAP_TYPE_CPUMAP);
	__uint(max_entries, 8);
	__type(key, __u32);
	__type(value, struct bpf_cpumap_val);
} cm SEC(".maps");

static __always_inline void count(void)
{
	__u32 k = 0;
	__u64 *v = bpf_map_lookup_elem(&cnt, &k);

	if (v)
		*v += 1;
}

SEC("xdp.frags")
int xdp_drop_cnt(struct xdp_md *ctx)
{
	count();
	return XDP_DROP;
}

SEC("xdp.frags")
int xdp_tx_cnt(struct xdp_md *ctx)
{
	count();
	return XDP_TX;
}

SEC("xdp.frags")
int xdp_redir_cnt(struct xdp_md *ctx)
{
	count();
	return bpf_redirect_map(&dm, 0, 0);
}

SEC("xdp.frags")
int xdp_cpu_cnt(struct xdp_md *ctx)
{
	count();
	return bpf_redirect_map(&cm, 2, 0);
}

char _license[] SEC("license") = "GPL";
