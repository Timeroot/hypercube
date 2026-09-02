"""mkbottles.py - write examples/bottles.hc, the ninety-nine bottles song.

usage: python mkbottles.py [output file]

The song text goes into a template of 512 bytes. The program reads one byte
of the template at each step. Eight byte values are markers:

    1  write the tens digit of the counter; skip it if the digit is 0
    2  write the ones digit of the counter
    3  write the letter s; skip it if the counter is 1
    4  go to the words "no more" if the counter is 0
    5  subtract 1 from the counter; write nothing
    6  the end of the verse; go to the last verse if the counter is 0,
       else go back to byte 0
    7  go back to the text after the third number
    8  the program is complete

The counter holds two decimal digits, so the program needs no division.
The marker 5 sits in the middle of the verse, at the place where the song
changes from n to n-1. Therefore the program needs only one counter.

The template lookup is a tree of choices on the 9 bits of the index. The
lazy rule of @ runs only one path of the tree, so a lookup is cheap.
"""
import sys

# ------------------------------------------------------------------
# the template
# ------------------------------------------------------------------

DIG10, DIG1, PLURAL, ZEROJ, DEC, ENDV, JUMP, STOPM = 1, 2, 3, 4, 5, 6, 7, 8

SIZE = 512      # the number of bytes of the template
DEPTH = 9       # the number of bits of the index
NOMORE = 128    # the address of the words "no more"
LAST = 160      # the address of the last verse

VERSE_A = b" bottle"
VERSE_B = b" of beer on the wall, "
VERSE_C = b" of beer.\nTake one down and pass it around, "
VERSE_D = b" of beer on the wall.\n\n"
LAST_VERSE = (b"No more bottles of beer on the wall, no more bottles of beer.\n"
              b"Go to the store and buy some more, 99 bottles of beer on the wall.\n\n")


def template():
    """Give the template and the address of the text after the third number."""
    t = [0] * SIZE

    def put(pos, data):
        for i, b in enumerate(data):
            t[pos + i] = b

    main = []
    main += [DIG10, DIG1]
    main += list(VERSE_A) + [PLURAL] + list(VERSE_B)
    main += [DIG10, DIG1]
    main += list(VERSE_A) + [PLURAL] + list(VERSE_C)
    main += [DEC]
    main += [ZEROJ]                 # go to "no more" if the counter is 0
    after = len(main) + 2           # the address of the text after the number
    main += [DIG10, DIG1]
    main += list(VERSE_A) + [PLURAL] + list(VERSE_D)
    main += [ENDV]
    if len(main) > NOMORE:
        raise SystemExit("the verse needs %d bytes; the limit is %d" %
                         (len(main), NOMORE))
    put(0, main)

    put(NOMORE, list(b"no more") + [JUMP])

    if LAST + len(LAST_VERSE) + 1 > SIZE:
        raise SystemExit("the last verse does not fit in the template")
    put(LAST, list(LAST_VERSE) + [STOPM])
    return t, after


# ------------------------------------------------------------------
# constants
# ------------------------------------------------------------------

def bitlist(value, width):
    """The bits of one number. The low bit is first."""
    return [(value >> i) & 1 for i in range(width)]


def constprog(bits):
    """A program that gives a constant cube. The input must have 0 inds."""
    if len(bits) == 1:
        return "TRUE" if bits[0] else "FALSE"
    half = len(bits) // 2
    return "(%s,%s)=" % (constprog(bits[:half]), constprog(bits[half:]))


def constant(bits):
    """The same, from an input with any number of inds."""
    return constprog(bits) + " ANDR"


# ------------------------------------------------------------------
# the path to one bit of the index
# ------------------------------------------------------------------

def bitpath(k, get_index):
    """A program that gives bit k of the index as a cube with 0 inds.

    The index cube has 4 inds. The first ind is the highest bit of the
    address. The program takes the choice for the highest address bit
    first, so the text holds the choices in the reverse order.
    """
    addr = bitlist(k, 4)
    steps = ["RIGHT" if a else "LEFT" for a in addr]
    return " ".join(steps) + " " + get_index


def mux(cond, ncond, yes, no):
    return "@(@(%s,%s)=,@(%s,%s)=)=" % (cond, yes, ncond, no)


# ------------------------------------------------------------------
# the lookup tree
# ------------------------------------------------------------------

def lookup(out, tab):
    """Write the definitions of the tree. The name of the root is CHAR."""
    out.append("; --- the template lookup ---")
    out.append("; B0 to B%d give one bit of the index. The lookup is a tree of" %
               (DEPTH - 1))
    out.append("; choices on those bits. Only one path of the tree runs.")
    for k in range(DEPTH):
        out.append("B%d := %s" % (k, bitpath(k, "LEFT")))
    out.append("")

    def name(prefix):
        return "CHAR" if not prefix else "T" + prefix

    def walk(prefix):
        if len(prefix) == DEPTH:
            value = int(prefix, 2)
            out.append("%s := %s" % (name(prefix), constant(bitlist(tab[value], 8))))
            return
        k = DEPTH - 1 - len(prefix)
        out.append("%s := %s" % (name(prefix),
                                 mux("===B%d" % k, "===NOT B%d" % k,
                                     name(prefix + "1"), name(prefix + "0"))))
        walk(prefix + "0")
        walk(prefix + "1")

    walk("")
    out.append("")


# ------------------------------------------------------------------
# the program
# ------------------------------------------------------------------

HEAD = """IO
; bottles.hc - the ninety-nine bottles of beer song.
; GENERATED by mkbottles.py. Do not edit this file.
;
;   hypercube examples/prelude.hc examples/arith.hc examples/bottles.hc
;
; --- the state ---
; The state is a cube with 5 inds:
;     ( idx , ( d1 , d0 ) )
; idx has 4 inds and holds the position in the template of 512 bytes.
; d1 and d0 have 3 inds. They hold the two decimal digits of the counter.
;
; --- the loop ---
; The interface gives the program a cube with 6 inds: (1,state).
; At the start the cube has 0 inds, so the probe P6 fails, and the handler
; of the block makes the first state. The counter starts at 99.
;
; Each step reads one byte of the template. A marker byte changes the state,
; and the program then calls itself. Any other byte goes to stdout.
"""

LOGIC = """
; --- the step ---
; STEP puts the template byte beside the state, so the program reads the
; byte one time only. The pair has 6 inds: (byte in 5 inds, state in 5 inds).

; The chain of choices is one expression inside the block, so the loop
; uses # and not the name STEP. A # cannot live in a name of its own.
STEP := [@(@(Q6,@(@(ZCNT,# GOLV)=,@(NZCNT,# ZEROI)=)=)=,@(R6,@(@(Q4,@(@(ZCNT,# GONM)=,@(NZCNT,# NEXTI)=)=)=,@(R4,@(@(Q7,# GOAF)=,@(R7,@(@(Q8,STOP)=,@(R8,@(@(Q5,# DECC)=,@(R5,@(@(Q3,@(@(ISONE,# NEXTI)=,@(NISONE,EMITS)=)=)=,@(R3,@(@(Q1,@(@(ZD1,# NEXTI)=,@(NZD1,EMIT1)=)=)=,@(R1,@(@(Q2,EMIT0)=,@(R2,EMITC)=)=)=)=)=)=)=)=)=)=)=)=)=)=)=)= (== CHAR,)=]

; --- parts of the pair ---
CH := LEFT LEFT LEFT       ; the template byte, 3 inds

; --- new states, 5 inds ---
NEXTI := (INCP LEFT,RIGHT)= RIGHT          ; idx + 1
ZEROI := (FALSE LEFT,RIGHT)= RIGHT         ; idx = 0
DECC  := (LEFT,DECB RIGHT)= NEXTI          ; idx + 1 and counter - 1
GONM  := (KNM,RIGHT)= RIGHT                ; go to the words "no more"
GOAF  := (KAF,RIGHT)= RIGHT                ; go back after the third number
GOLV  := (KLV,RIGHT)= RIGHT                ; go to the last verse

; The counter holds two decimal digits, so a step down is:
;   d0 is not 0 : (d1, d0 - 1)
;   d0 is 0     : (d1 - 1, 9)
DECB  := @(@(ZD0,(DEC LEFT,K9)=)=,@(NZD0,(LEFT,DEC RIGHT)=)=)=
ZD0   := = EQ0 RIGHT
NZD0  := = ANY RIGHT

; --- tests on the template byte, 7 inds ---
Q1 := ==== ALL XNOR (CH,K01)=
R1 := ==== ANY XOR (CH,K01)=
Q2 := ==== ALL XNOR (CH,K02)=
R2 := ==== ANY XOR (CH,K02)=
Q3 := ==== ALL XNOR (CH,K03)=
R3 := ==== ANY XOR (CH,K03)=
Q4 := ==== ALL XNOR (CH,K04)=
R4 := ==== ANY XOR (CH,K04)=
Q5 := ==== ALL XNOR (CH,K05)=
R5 := ==== ANY XOR (CH,K05)=
Q6 := ==== ALL XNOR (CH,K06)=
R6 := ==== ANY XOR (CH,K06)=
Q7 := ==== ALL XNOR (CH,K07)=
R7 := ==== ANY XOR (CH,K07)=
Q8 := ==== ALL XNOR (CH,K08)=
R8 := ==== ANY XOR (CH,K08)=

; --- tests on the counter, 7 inds ---
ZCNT  := === EQ0 RIGHT RIGHT        ; the counter is 0
NZCNT := === ANY RIGHT RIGHT
ZD1   := ==== EQ0 LEFT RIGHT RIGHT  ; the tens digit is 0
NZD1  := ==== ANY LEFT RIGHT RIGHT

; The counter is 1 when the tens digit is 0 and the ones digit is 1.
ONEC1  := AND (EQ0 LEFT RIGHT RIGHT,ALL XNOR (RIGHT RIGHT RIGHT,K1)=)=
ISONE  := ==== ONEC1
NISONE := ==== NOT ONEC1

; --- the write request, 7 inds ---
; The request is (1,((1,a),newstate)). The part a has 16 bits and holds the
; byte in the 8 low bits.
EMITC := (TRUE,((TRUE LEFT LEFT,(CH,FALSE LEFT LEFT LEFT)=)=,NEXTI)=)=
EMIT0 := (TRUE,((TRUE LEFT LEFT,(CD0,FALSE LEFT LEFT LEFT)=)=,NEXTI)=)=
EMIT1 := (TRUE,((TRUE LEFT LEFT,(CD1,FALSE LEFT LEFT LEFT)=)=,NEXTI)=)=
EMITS := (TRUE,((TRUE LEFT LEFT,(KS,FALSE LEFT LEFT LEFT)=)=,NEXTI)=)=

; A digit character is the digit with the bits of 0x30.
CD0 := OR (K30,RIGHT RIGHT RIGHT)=
CD1 := OR (K30,LEFT RIGHT RIGHT)=

; A cube of false bits gives (0,x), so the program is complete.
STOP := FALSE =


; --- the start ---
P6   := ((((((,),),),),),)
MAIN := [STEP RIGHT P6,STEP INIT]
"""


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "examples/bottles.hc"
    tab, after = template()
    out = [HEAD]

    out.append("; --- constants ---")
    marks = (("K01", DIG10), ("K02", DIG1), ("K03", PLURAL), ("K04", ZEROJ),
             ("K05", DEC), ("K06", ENDV), ("K07", JUMP), ("K08", STOPM),
             ("K30", 0x30), ("K9", 9), ("K1", 1), ("KS", ord("s")))
    for name, value in marks:
        out.append("%s := %s" % (name, constant(bitlist(value, 8))))
    for name, value in (("KNM", NOMORE), ("KAF", after), ("KLV", LAST)):
        out.append("%s := %s" % (name, constant(bitlist(value, 16))))

    # The first state: the index is 0 and the counter is 99.
    out.append("INIT := %s" % constant(bitlist(0, 16) + bitlist(9, 8) + bitlist(9, 8)))
    out.append("")

    lookup(out, tab)
    out.append(LOGIC)

    text = "\n".join(out) + "\n"
    with open(path, "w", newline="\n") as f:
        f.write(text)
    print("wrote %s: %d bytes of source, template of %d bytes, jump back to %d" %
          (path, len(text), SIZE, after))


if __name__ == "__main__":
    main()
