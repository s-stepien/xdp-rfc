all: bench.bpf.o

%.bpf.o: %.bpf.c
	clang -O2 -g --target=bpf -c $< -o $@

clean:
	rm -f bench.bpf.o
