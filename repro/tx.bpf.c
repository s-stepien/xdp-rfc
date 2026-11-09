// SPDX-License-Identifier: GPL-2.0
/* Bounce packets back with XDP_TX so veth turns the buff into an xdp_frame,
 * optionally after trimming all fragments.
 */
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

__u64 txed = 0;

static __always_inline int bounce(struct xdp_md *ctx, int shrink)
{
	void *data = (void *)(long)ctx->data;
	void *data_end = (void *)(long)ctx->data_end;
	int linear = data_end - data;
	int total = bpf_xdp_get_buff_len(ctx);

	if (total <= linear)
		return XDP_PASS;
	if (shrink && bpf_xdp_adjust_tail(ctx, -(total - linear)))
		return XDP_PASS;
	__sync_fetch_and_add(&txed, 1);
	return XDP_TX;
}

SEC("xdp.frags")
int xdp_tx_frags(struct xdp_md *ctx)
{
	return bounce(ctx, 0);
}

SEC("xdp.frags")
int xdp_tx_shrink(struct xdp_md *ctx)
{
	return bounce(ctx, 1);
}

SEC("xdp.frags")
int xdp_pass(struct xdp_md *ctx)
{
	return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
