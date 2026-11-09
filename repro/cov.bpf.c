// SPDX-License-Identifier: GPL-2.0
/* Small helper programs for the veth tests (dm.sh uses xdp_pass_cnt). */
#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

__u64 bounced = 0, passed = 0, redirected = 0, trimmed = 0;

static __always_inline int is_ipv4(struct xdp_md *ctx, struct ethhdr **eth)
{
	void *data = (void *)(long)ctx->data;
	void *data_end = (void *)(long)ctx->data_end;

	*eth = data;
	if (data + sizeof(**eth) > data_end)
		return 0;
	return (*eth)->h_proto == bpf_htons(ETH_P_IP);
}

/* Send IPv4 back to the peer with MACs swapped so it accepts the frame. */
SEC("xdp.frags")
int xdp_bounce_swap(struct xdp_md *ctx)
{
	unsigned char tmp[ETH_ALEN];
	struct ethhdr *eth;

	if (!is_ipv4(ctx, &eth))
		return XDP_PASS;
	__builtin_memcpy(tmp, eth->h_dest, ETH_ALEN);
	__builtin_memcpy(eth->h_dest, eth->h_source, ETH_ALEN);
	__builtin_memcpy(eth->h_source, tmp, ETH_ALEN);
	__sync_fetch_and_add(&bounced, 1);
	return XDP_TX;
}

SEC("xdp.frags")
int xdp_pass_cnt(struct xdp_md *ctx)
{
	__sync_fetch_and_add(&passed, 1);
	return XDP_PASS;
}

/* xdp_do_redirect() fails for a missing ifindex: exercises err_xdp. */
SEC("xdp.frags")
int xdp_redirect_bad(struct xdp_md *ctx)
{
	struct ethhdr *eth;

	if (!is_ipv4(ctx, &eth))
		return XDP_PASS;
	__sync_fetch_and_add(&redirected, 1);
	return bpf_redirect(0x7ffffff0, 0);
}

/* Trim all frags, then let the packet continue. */
SEC("xdp.frags")
int xdp_trim_pass(struct xdp_md *ctx)
{
	int linear = (long)ctx->data_end - (long)ctx->data;
	int total = bpf_xdp_get_buff_len(ctx);

	if (total > linear && !bpf_xdp_adjust_tail(ctx, -(total - linear)))
		__sync_fetch_and_add(&trimmed, 1);
	return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
