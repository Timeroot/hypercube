"""drive.py - run an IO program step by step, and show every request.

usage: python drive.py <files...> -- <program text> [stdin bytes]

This is the same loop as the interpreter, but it prints what happens at
each step. It helps to find the fault in a program that does not stop.
"""
import subprocess
import sys


def run(files, entry, data, timeout=300):
    cmd = ["./hypercube.exe"] + files + ["--no-io", "-i", data, "--raw"]
    if entry:
        cmd += ["--entry", entry]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "timeout"
    if out.returncode != 0:
        return None, out.stderr.strip()[:100]
    return out.stdout.strip(), None


def halves(bits):
    h = len(bits) // 2
    return bits[:h], bits[h:]


def main():
    argv = sys.argv[1:]
    cut = argv.index("--")
    files = argv[:cut]
    rest = argv[cut + 1:]
    prog = rest[0] if rest else ""
    data = (prog + "\n" + (rest[1] if len(rest) > 1 else "")).encode("latin-1")

    cube = "0"
    pos = 0
    out = bytearray()
    for step in range(int(rest[2]) if len(rest) > 2 else 40):
        res, err = run(files, None, cube)
        if err:
            print("step %d: FAILED: %s" % (step, err))
            return 1
        tag, rest2 = halves(res)
        if "1" not in tag:
            print("step %d: complete after %d bytes of output" % (step, len(out)))
            break
        x, y = halves(rest2)
        if "1" not in x:
            ch = data[pos] if pos < len(data) else -1
            pos += 1
            b = ["0"] * len(x)
            if ch < 0:
                if len(b) > 8:
                    b[8] = "1"
            else:
                for i in range(8):
                    if (ch >> i) & 1:
                        b[i] = "1"
            print("step %-3d READ  %-4r cube=%d state=%d" %
                  (step, chr(ch) if ch >= 0 else "EOF", len(res), len(y)))
            cube = "1" * (len(x) + len(y)) + "".join(b) + y
        else:
            one, a = halves(x)
            byte = sum(1 << i for i in range(8) if a[i] == "1")
            out.append(byte)
            print("step %-3d WRITE %-4r cube=%d state=%d" %
                  (step, chr(byte), len(res), len(y)))
            cube = "1" * len(y) + y
    print("output: %r" % bytes(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
