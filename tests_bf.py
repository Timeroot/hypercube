"""tests_bf.py - check the Brainfuck interpreter against python.

usage: python tests_bf.py

Each case gives a Brainfuck program and the bytes of stdin after it.
"""
import subprocess
import sys
import time

BF = sys.argv[1] if len(sys.argv) > 1 else "examples/bf.hc"
HC = (["./hypercube.exe", BF] if BF.endswith(".txt") else
      ["./hypercube.exe", "examples/prelude.hc", "examples/arith.hc",
       "examples/mem.hc", BF])

CASES = [
    ("print A", "++++++++[>++++++++<-]>+.", ""),
    ("two bytes", "++++++++++[>++++++>+++++++<<-]>++.>+.", ""),
    ("cat", ",[.,]", "hi there!\n"),
    ("cat empty", ",[.,]", ""),
    ("echo one", ",.", "Z"),
    ("add two", ",>,<[->+<]>.", "\x02\x03"),
    ("nested loops", "+++[>+++[>+++<-]<-]>>.", ""),
    ("skip a loop", "[->+<]+.", ""),
    ("comments", "++ this is text +. and more", ""),
    ("move left", "+++>+++<[->+<]>.", ""),
    ("hello", "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]"
              ">>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.", ""),
    ("wide tape", ">>>>>>>>>>>>>>>>>>>>+++++++++++++++++++++++++++++++++.", ""),
    ("far cell", ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>+++++++++++++++++++++++++++++++++++.<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<+.", ""),
]


def reference(prog, data):
    """A simple Brainfuck interpreter, for the comparison."""
    tape = [0] * 4096
    out = bytearray()
    src = [c for c in prog]
    jump = {}
    stack = []
    for i, c in enumerate(src):
        if c == "[":
            stack.append(i)
        elif c == "]":
            j = stack.pop()
            jump[i], jump[j] = j, i
    ip = tp = 0
    pos = 0
    data = data.encode("latin-1")
    while ip < len(src):
        c = src[ip]
        if c == ">":
            tp += 1
        elif c == "<":
            tp -= 1
        elif c == "+":
            tape[tp] = (tape[tp] + 1) % 256
        elif c == "-":
            tape[tp] = (tape[tp] - 1) % 256
        elif c == ".":
            out.append(tape[tp])
        elif c == ",":
            tape[tp] = data[pos] if pos < len(data) else 0
            pos += 1
        elif c == "[" and tape[tp] == 0:
            ip = jump[ip]
        elif c == "]" and tape[tp] != 0:
            ip = jump[ip]
        ip += 1
    return bytes(out)


def main():
    bad = 0
    for name, prog, data in CASES:
        want = reference(prog, data)
        start = time.time()
        out = subprocess.run(HC, input=(prog + "\n" + data).encode("latin-1"),
                             capture_output=True)
        elapsed = time.time() - start
        got = out.stdout
        mark = "ok" if got == want else "BAD"
        if got != want:
            bad += 1
        print("%-14s %5.1fs %-3s got %-22r want %r" %
              (name, elapsed, mark, got[:20], want[:20]))
        if out.returncode != 0:
            print("    exit %d: %s" % (out.returncode, out.stderr.decode()[:120]))
    print("-- results: %d cases, %d fail --" % (len(CASES), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
