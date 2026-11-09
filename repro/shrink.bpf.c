// SPDX-License-Identifier: GPL-2.0
/* Trim every fragment of a multi-buffer XDP packet, forcing
 * bpf_xdp_shrink_data() to release the fragment pages via __xdp_return().
 */
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

__u64 shrunk = 0;

SEC("xdp.frags")
int xdp_shrink_frags(struct xdp_md *ctx)
{
	void *data = (void *)(long)ctx->data;
	void *data_end = (void *)(long)ctx->data_end;
	int linear = data_end - data;
	int total = bpf_xdp_get_buff_len(ctx);

	if (total > linear && !bpf_xdp_adjust_tail(ctx, -(total - linear)))
		__sync_fetch_and_add(&shrunk, 1);

	return XDP_DROP;
}

char _license[] SEC("license") = "GPL";
