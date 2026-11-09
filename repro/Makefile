# Rebuild the BPF objects and the devmap loader.
BPF_OBJS := bench.bpf.o cov.bpf.o dmegress.bpf.o peer.bpf.o shrink.bpf.o tx.bpf.o

all: $(BPF_OBJS) dmload

%.bpf.o: %.bpf.c
	clang -O2 -g --target=bpf -c $< -o $@

dmload: dmload.c
	$(CC) -O2 -o $@ $< -lbpf

clean:
	rm -f $(BPF_OBJS) dmload

.PHONY: all clean
