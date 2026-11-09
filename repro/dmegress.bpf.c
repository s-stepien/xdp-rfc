// SPDX-License-Identifier: GPL-2.0
/* veth -> devmap -> egress program that trims all frags. */
#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

struct {
	__uint(type, BPF_MAP_TYPE_DEVMAP);
	__uint(key_size, sizeof(__u32));
	__uint(value_size, sizeof(struct bpf_devmap_val));
	__uint(max_entries, 1);
} dm SEC(".maps");

__u64 redirected = 0, egress_runs = 0, trimmed = 0;

/* On v1: send every IPv4 packet to devmap slot 0 (v2). */
SEC("xdp.frags")
int xdp_redir(struct xdp_md *ctx)
{
	void *data = (void *)(long)ctx->data;
	struct ethhdr *eth = data;

	if (data + sizeof(*eth) > (void *)(long)ctx->data_end ||
	    eth->h_proto != bpf_htons(ETH_P_IP))
		return XDP_PASS;
	__sync_fetch_and_add(&redirected, 1);
	return bpf_redirect_map(&dm, 0, 0);
}

/* Devmap egress program: trim all frags, then transmit. */
SEC("xdp.frags/devmap")
int xdp_egress_trim(struct xdp_md *ctx)
{
	int linear = (long)ctx->data_end - (long)ctx->data;
	int total = bpf_xdp_get_buff_len(ctx);

	__sync_fetch_and_add(&egress_runs, 1);
	if (total > linear && !bpf_xdp_adjust_tail(ctx, -(total - linear)))
		__sync_fetch_and_add(&trimmed, 1);
	return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
