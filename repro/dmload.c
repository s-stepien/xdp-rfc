// SPDX-License-Identifier: GPL-2.0
/* dmload <obj> <redirect ifname> <target ifname>: attach xdp_redir in
 * native mode and point devmap slot 0 at the target with the egress
 * program. Must run in the netns of both devices.
 */
#include <stdio.h>
#include <net/if.h>
#include <linux/if_link.h>
#include <bpf/libbpf.h>
#include <bpf/bpf.h>

int main(int argc, char **argv)
{
	struct bpf_object *obj;
	struct bpf_devmap_val val = {};
	int rx, tx, key = 0, err;

	if (argc != 4)
		return 2;
	rx = if_nametoindex(argv[2]);
	tx = if_nametoindex(argv[3]);
	obj = bpf_object__open_file(argv[1], NULL);
	if (!obj || bpf_object__load(obj)) {
		fprintf(stderr, "load failed\n");
		return 1;
	}
	val.ifindex = tx;
	val.bpf_prog.fd = bpf_program__fd(bpf_object__find_program_by_name(obj, "xdp_egress_trim"));
	err = bpf_map_update_elem(bpf_object__find_map_fd_by_name(obj, "dm"), &key, &val, 0);
	if (err) {
		fprintf(stderr, "devmap update failed: %d\n", err);
		return 1;
	}
	err = bpf_xdp_attach(rx, bpf_program__fd(bpf_object__find_program_by_name(obj, "xdp_redir")),
			     XDP_FLAGS_DRV_MODE, NULL);
	if (err) {
		fprintf(stderr, "xdp attach failed: %d\n", err);
		return 1;
	}
	printf("loaded: redirect %s(%d) -> devmap -> %s(%d) with egress prog\n",
	       argv[2], rx, argv[3], tx);
	return 0;
}
