// SPDX-License-Identifier: GPL-2.0
/* Count every packet the program sees, then pass it. pass_cnt has no frags
 * support (the case where generic XDP has to linearize), pass_cnt_frags has.
 */
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u64);
} cnt SEC(".maps");

static __always_inline int count_pass(void)
{
	__u32 k = 0;
	__u64 *v = bpf_map_lookup_elem(&cnt, &k);

	if (v)
		*v += 1;
	return XDP_PASS;
}

SEC("xdp")
int pass_cnt(struct xdp_md *ctx)
{
	return count_pass();
}

SEC("xdp.frags")
int pass_cnt_frags(struct xdp_md *ctx)
{
	return count_pass();
}

char _license[] SEC("license") = "GPL";
