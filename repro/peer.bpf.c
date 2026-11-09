// SPDX-License-Identifier: GPL-2.0
/* veth_xdp_rcv_one() reproducer: v1 bounces multi-buffer packets back
 * with XDP_TX (so v0 receives them as xdp_frames), v0 trims all frags
 * of those frames and drops them.
 */
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

__u64 bounced = 0;
__u64 trimmed = 0;

SEC("xdp.frags")
int xdp_bounce(struct xdp_md *ctx)
{
	int linear = (long)ctx->data_end - (long)ctx->data;

	if (bpf_xdp_get_buff_len(ctx) <= linear)
		return XDP_PASS;
	__sync_fetch_and_add(&bounced, 1);
	return XDP_TX;
}

SEC("xdp.frags")
int xdp_trim_drop(struct xdp_md *ctx)
{
	int linear = (long)ctx->data_end - (long)ctx->data;
	int total = bpf_xdp_get_buff_len(ctx);

	if (total <= linear)
		return XDP_PASS;
	if (bpf_xdp_adjust_tail(ctx, -(total - linear)))
		return XDP_PASS;
	__sync_fetch_and_add(&trimmed, 1);
	return XDP_DROP;
}

char _license[] SEC("license") = "GPL";
