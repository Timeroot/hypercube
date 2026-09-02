CXX      ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra
# The interpreter uses the C++ stack for the recursion of the language.
# A large stack lets the depth limit stop a loop before the stack is full.
LDFLAGS  ?= -Wl,--stack,268435456

all: hypercube

hypercube: hypercube.cpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $<

test: hypercube
	sh tests.sh

LIB = examples/prelude.hc examples/arith.hc examples/mem.hc

# The programs without names. The expander needs the IO line at the start,
# because that line is a header of the file and not a part of the program.
nameless: hypercube
	mkdir -p nameless
	echo IO > nameless/bf-nameless.txt
	./hypercube $(LIB) examples/bf.hc --expand >> nameless/bf-nameless.txt
	echo IO > nameless/bfu-nameless.txt
	./hypercube $(LIB) examples/bfu.hc --expand >> nameless/bfu-nameless.txt
	echo IO > nameless/bottles-nameless.txt
	./hypercube examples/prelude.hc examples/arith.hc examples/bottles.hc --expand >> nameless/bottles-nameless.txt

clean:
	rm -f hypercube hypercube.exe

.PHONY: all test clean nameless
