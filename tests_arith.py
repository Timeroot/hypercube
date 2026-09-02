"""tests_arith.py - check the arithmetic programs against python.

usage: python tests_arith.py [inds]

The default is 2 inds, which gives numbers of 4 bits.
"""
import subprocess
import sys
import itertools

HC = ["./hypercube.exe", "examples/prelude.hc", "examples/arith.hc"]


def bits(value, width):
    """The bits of one number. The low bit comes first."""
    return "".join("1" if (value >> i) & 1 else "0" for i in range(width))


def value(text):
    return sum(1 << i for i, ch in enumerate(text) if ch == "1")


def run(entry, data):
    out = subprocess.run(HC + ["--entry", entry, "-i", data, "--raw"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return "error: " + out.stderr.strip()
    return out.stdout.strip()


def main():
    inds = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    width = 1 << inds
    mod = 1 << width
    numbers = list(range(mod))
    bad = 0
    total = 0

    def check(name, entry, data, want):
        nonlocal bad, total
        total += 1
        got = run(entry, data)
        if got != bits(want, width):
            bad += 1
            print("FAIL %-4s %s -> got %s want %s" % (name, data, got, bits(want, width)))

    print("width = %d bits" % width)

    for x in numbers:
        check("INC", "INC", bits(x, width), (x + 1) % mod)
        check("DEC", "DEC", bits(x, width), (x - 1) % mod)
    print("INC and DEC: %d cases" % (2 * len(numbers)))

    for x, y in itertools.product(numbers, numbers):
        pair = bits(x, width) + bits(y, width)
        check("ADD", "ADD", pair, (x + y) % mod)
        check("SUB", "SUB", pair, (x - y) % mod)
    print("ADD and SUB: %d cases" % (2 * len(numbers) ** 2))

    for x, y in itertools.product(numbers, numbers):
        pair = bits(x, width) + bits(y, width)
        check("MUL", "MUL", pair, (x * y) % mod)
        check("MULS", "MULS", pair, (x * y) % mod)
    print("MUL and MULS: %d cases" % (2 * len(numbers) ** 2))

    print("-- results: %d checks, %d fail --" % (total, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
