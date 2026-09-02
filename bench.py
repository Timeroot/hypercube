"""bench.py - compare the two multiplication programs.

usage: python bench.py [inds] [max x]

The default is 4 inds. A cube with 4 inds holds 16 bits. The number 7! is
5040, and 5040 needs 13 bits. Therefore 4 inds is the smallest cube for 7!.
"""
import math
import subprocess
import sys
import time

HC = ["./hypercube.exe", "examples/prelude.hc", "examples/arith.hc"]


def bits(value, width):
    return "".join("1" if (value >> i) & 1 else "0" for i in range(width))


def value(text):
    return sum(1 << i for i, ch in enumerate(text) if ch == "1")


def run(entry, data, repeat=3):
    """Run one program. Give the result, the best time and the counts."""
    best = None
    out = None
    for _ in range(repeat):
        start = time.perf_counter()
        out = subprocess.run(HC + ["--entry", entry, "-i", data, "--raw", "--stats"],
                             capture_output=True, text=True)
        elapsed = time.perf_counter() - start
        best = elapsed if best is None else min(best, elapsed)
    counts = {}
    for part in out.stderr.split():
        if "=" in part:
            key, _, num = part.partition("=")
            counts[key] = int(num)
    return out.stdout.strip(), best, counts


def main():
    inds = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    top = int(sys.argv[2]) if len(sys.argv) > 2 else 7
    width = 1 << inds
    mod = 1 << width

    # The start time of the process is not part of the work.
    _, base, _ = run("ONEC", bits(0, width), repeat=5)
    print("cube: %d inds, %d bits, modulo %d" % (inds, width, mod))
    print("process start time: %.0f ms (this time is subtracted below)" % (base * 1000))
    print()
    print("%3s %7s | %9s %12s | %9s %12s | %6s" %
          ("x", "x!", "FACTS ms", "FACTS nands", "FACT ms", "FACT nands", "faster"))
    print("-" * 78)

    bad = 0
    for x in range(top + 1):
        want = math.factorial(x) % mod
        slow, ts, cs = run("FACTS", bits(x, width))
        fast, tf, cf = run("FACT", bits(x, width))
        if value(slow) != want or value(fast) != want:
            bad += 1
            print("FAIL at x = %d" % x)
            continue
        ms = max(ts - base, 0.0) * 1000
        mf = max(tf - base, 0.0) * 1000
        ratio = (ms / mf) if mf > 0.05 else float("nan")
        print("%3d %7d | %9.1f %12d | %9.1f %12d | %5.1fx" %
              (x, want, ms, cs["nand-steps"], mf, cf["nand-steps"], ratio))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
