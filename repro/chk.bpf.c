// SPDX-License-Identifier: GPL-2.0
/* For shared-skb copies: count packets and check that the program sees
 * the frame from the MAC header on (IPv4 to 10.9.0.2) and its full length.
 * vals[0] = seen, vals[1] = headers ok, vals[2] = length of the last frame
 * with ok headers (per CPU), vals[3] = such frames whose length differs from
 * the previous one.
 */
#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 4);
	__type(key, __u32);
	__type(value, __u64);
} cnt SEC(".maps");

static __always_inline void inc(__u32 k)
{
	__u64 *v = bpf_map_lookup_elem(&cnt, &k);

	if (v)
		*v += 1;
}

static __always_inline int check(struct xdp_md *ctx, __u32 len)
{
	void *data = (void *)(long)ctx->data;
	void *end = (void *)(long)ctx->data_end;
	struct ethhdr *eth = data;
	struct iphdr *ip = data + sizeof(*eth);
	__u32 k;
	__u64 *v;

	inc(0);
	if ((void *)(ip + 1) <= end && eth->h_proto == bpf_htons(ETH_P_IP) &&
	    ip->daddr == bpf_htonl(0x0a090002) && ip->version == 4) {
		inc(1);
		k = 2;
		v = bpf_map_lookup_elem(&cnt, &k);
		if (v) {
			if (*v && *v != len)
				inc(3);
			*v = len;
		}
	}
	return XDP_PASS;
}

SEC("xdp")
int chk(struct xdp_md *ctx)
{
	return check(ctx, ctx->data_end - ctx->data);
}

SEC("xdp.frags")
int chk_frags(struct xdp_md *ctx)
{
	return check(ctx, bpf_xdp_get_buff_len(ctx));
}

char _license[] SEC("license") = "GPL";
