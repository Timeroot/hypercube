# hypercube

hypercube is an esoteric functional language. The memory of a program is a
hypercube of bits. A program changes the memory with two operations: a NAND
operation and a copy operation. NAND is universal for computation. Therefore
these two operations are sufficient for all boolean functions.

This directory holds an interpreter in C++, a library of programs, and two
interpreters for Brainfuck written in the language itself. The section
"Notes on the semantics" lists the points that the two operations alone do
not settle.

## Build

    make                      # or: g++ -std=c++17 -O2 -Wl,--stack,268435456 -o hypercube hypercube.cpp
    make test                 # or: sh tests.sh
    python tests_arith.py 2   # check the arithmetic against python
    python bench.py 4 7       # compare the two multiplication programs
    python mkbottles.py       # write examples/bottles.hc again
    python tests_bf.py        # check the Brainfuck interpreter against python
    python tests_bf.py examples/bfu.hc   # the same, for the version that grows
    make nameless             # write the programs without names

The interpreter uses the C++ stack for the recursion of the language. The
large stack lets the depth limit stop a program before the stack is full.

## Run

    ./hypercube examples/prelude.hc -e 'NOT' -i 1011
    inds=2 bits=0100

## The memory

The memory is one cube of bits. The cube has `n` inds. An "ind" is one index
of the cube. The cube holds `2^n` bits. The value of `n` can be 0. A cube with
0 inds holds one bit.

The first ind divides the cube into two halves. The left half holds the bits
with the first index 0. The right half holds the bits with the first index 1.
Each half is a cube with `n-1` inds.

The interpreter prints the bits in index order. The first ind is the most
significant index. Example: the cube `((0,1),(1,1))` has 2 inds. Its bits are
`0111`. Its left half is `01`.

## The two operations

| Program | Name | Effect on the inds |
|---------|------|--------------------|
| `=`     | copy | `n` becomes `n+1`  |
| `@`     | NAND | `n` becomes `n-1`  |

`=` adds a new first ind. The two halves of the result are equal to the
input. The operation is always valid.

`@` applies NAND to the two halves. It removes the first ind. For each
position `i`, the result is `in[0][i] NAND in[1][i]`. The input must have one
ind or more. If the input has 0 inds, the operation fails.

**A program runs from right to left.** The rightmost part runs first. This
order comes from the notation of function composition.

Example: `@=` is the program NOT. First `=` makes a copy of every bit. Then
`@` applies NAND to each bit and its copy. `x NAND x` is `NOT x`.

The empty program is the identity program. The programs `@=@=` and `@@==` are
also identity programs.

## Splits

    ( A , B )

A split divides the cube at the first ind. It runs the program `A` on the left
half. It runs the program `B` on the right half. It then joins the two results
into one cube.

The input must have one ind or more. The two results must have the same number
of inds. If the numbers are different, the split fails. The option `--pad`
changes this behaviour: the interpreter adds `=` operations to the smaller
result until the two numbers are equal.

Example: `@(@=,)=` copies the cube, applies NOT to the left half, and applies
NAND to the two halves. The result of `NAND(NOT x, x)` is always true.
Therefore this program makes all bits true.

## Names

    NAME := PROGRAM

A source line can give a name to a program. Other programs can then use the
name. A name starts with a letter or an underscore.

    NOT   := @=
    TRUE  := @(NOT,)=
    FALSE := NOT TRUE

A statement ends at the end of a line. A statement continues on the next line
if a bracket is open. The character `;` starts a comment. The comment ends at
the end of the line.

A name can refer to a name that comes later in the file. A name can also refer
to itself. Such a program does not stop, and the interpreter stops it at the
depth limit.

## Blocks and loops

    [ BODY ]
    [ BODY , HANDLER ]

A block gives a name to the program inside the square brackets. The symbol `#`
runs the block again. This gives recursion, and therefore loops.

The symbol `#` refers to the innermost block. Add one `&` character for each
level above it:

| Symbol | Block |
|--------|-------|
| `#`    | the innermost block |
| `#&`   | the block one level above |
| `#&&`  | the block two levels above |

A split does not make a new block level. Only the square brackets make a
level. The interpreter reports a source error if the program has too few
levels. The programs `@#=` and `@[(#&,)]=` are examples of this error.

## Failures and handlers

Three events make a failure:

1. The program applies `@` to a cube with 0 inds.
2. The program applies a split to a cube with 0 inds.
3. The two halves of a split give a different number of inds.

The `HANDLER` part of a block catches a failure. The handler then runs on the
input of the block. A block without a comma does not catch a failure. In that
case the failure goes to the level above.

This is the standard loop over all inds:

    ALL := [=#@=@,]

The body applies AND (`@=@`) to the two halves. Then it calls itself with `#`.
Then it applies `=` to the result. The cube becomes smaller at each step. The
call with 0 inds cannot apply `@`, so it fails. The handler is empty, so that
call returns its input without a change. Each level then applies `=`. The
result is the AND of all bits, at every position of the original cube.

    EQ0 := ALL NOT

`EQ0` gives true at every position if every input bit is false.

## Lazy evaluation

`NAND(false, y)` is true for every value of `y`. The interpreter uses this
rule. For the program `@(X,Y)` it runs `X` first. If the result of `X` holds
only false bits, the interpreter does not run `Y`. It returns a cube of true
bits.

This rule lets a program stop even if the recursion has no end condition:

    [@(NOT,#)]=

For the input bit 1, the program makes the cube `(1,1)`. The part `NOT` gives
0 on the left half. The left half is all false, so `#` never runs. The result
is the single bit 1.

The same program with the parts in the other order does not stop:

    [@(#,NOT)]=

The interpreter must run the left part first, so the recursion continues. The
cube loses one ind at each step, and the program fails at 0 inds.

The interpreter applies the lazy rule to these forms:

* `@(X,Y)`
* `@ P (X,Y)`, where `P` is any program. The interpreter runs `P` first.
* `@ NAME`, if the name leads to one of these forms.
* `@ [ ... ]`, for the body and for the handler of the block.

The interpreter does not apply the lazy rule to a form such as `@@=(X,Y)`.
Such a form needs a test for true bits after the NOT operation.

## Grammar

    file    := statement*
    statement := [ IDENT ':=' ] seq
    seq     := item*                  ; the items run from right to left
    item    := '@' | '=' | split | block | recur | IDENT
    split   := '(' seq ',' seq ')'
    block   := '[' seq [ ',' seq ] ']'
    recur   := '#' '&'*
    IDENT   := [A-Za-z_][A-Za-z_0-9]*

## The interpreter

    usage: hypercube [options] [file.hc ...]

      -e, --expr SRC     use SRC as source text
      -i, --input BITS   the start cube, as 0 and 1 characters; use - for stdin
      -d, --inds N       a start cube of N inds with all bits false
          --entry NAME   run this definition
          --pad          pad a short split half with = instead of a failure
          --nested       also print the result in the ((a,b),(c,d)) form
          --trace        print each step to stderr
          --raw          print only the result bits
          --parse-only   check the syntax, then stop
          --expand       print the program again with no names
          --max-expand N the size limit of --expand (default 64000000)
          --stats        print the operation counts to stderr
          --no-io        ignore the IO header; run the program one time
          --max-inds N   the cube size limit (default 24)
          --max-depth N  the call depth limit (default 100000)
      -h, --help         print this text

The interpreter joins all files and all `-e` texts in the given order. The
length of the input must be a power of 2.

The interpreter selects the entry point with these rules, in this order:

1. the definition of the `--entry` name;
2. the last statement without a name;
3. the definition with the name `MAIN`;
4. the last definition in the source.

The exit code is 0 for a success, 1 for a failure of the program, 2 for an
error in the source, and 3 for a limit of the interpreter.

The two limits are safety limits of the interpreter, not parts of the
language. A handler cannot catch them. A `--max-depth` value above 500000 can
fill the C++ stack of the interpreter.

## The example files

`examples/prelude.hc` holds the basic programs:

| Name | Program | Effect |
|------|---------|--------|
| `NOT` | `@=` | NOT at each position |
| `TRUE` | `@(NOT,)=` | all bits become true |
| `FALSE` | `NOT TRUE` | all bits become false |
| `NAND` `AND` `OR` `NOR` `XOR` `XNOR` | | a gate on a cube with the shape `(a,b)` |
| `IF` | `@@((,NOT),)` | a choice; see below |
| `ALL` | `[=#@=@,]` | the AND of all bits, at every position |
| `EQ0` | `ALL NOT` | true everywhere if all bits are false |
| `ANY` | `NOT EQ0` | true everywhere if one bit or more is true |

`IF` takes a cube with the shape `((a,a),(b,c))`. The two `a` parts must be
equal. The result holds `b` where `a` is true, and `c` where `a` is false. The
result has two inds less than the input.

    ./hypercube examples/prelude.hc -e 'IF' -i 10101100
    inds=1 bits=10

`examples/reduce.hc` holds `PARITY`, `ANYOF` and `EQ`. `examples/lazy.hc`
holds the demonstration of the lazy rule. `examples/mem.hc` holds a byte
array with a one-hot mask for the index. `examples/cat.hc`,
`examples/bottles.hc` and `examples/bf.hc` use the IO interface; see
"Input and output".

## Arithmetic

`examples/arith.hc` holds binary arithmetic. A cube with `n` inds holds a
number of `2^n` bits. The bit at flat index `i` has the place value `2^i`.
Therefore the left half of a cube holds the low bits, and the right half
holds the high bits. All operations work modulo `2^(2^n)`.

The interpreter prints the low bit first. The 4-bit number 3 is `1100`.

`ADD`, `SUB`, `MUL` and `MULS` take a cube with the shape `(x,y)`. This cube
has one ind more than the two numbers. The result has the same inds as `x`.

    ./hypercube examples/prelude.hc examples/arith.hc --entry ADD -i 11001010
    inds=2 bits=0001                                   ; 3 + 5 = 8

| Name | Input | Effect |
|------|-------|--------|
| `LEFT` `RIGHT` | `n` inds | the low half or the high half |
| `MSBBC` `LSBBC` | `n` inds | the highest or lowest bit at every position |
| `ONEC` | `n` inds | the number 1 |
| `SHL` `SHR` | a number | multiply or divide by 2 |
| `INC` `DEC` | a number | add 1 or subtract 1 |
| `INCP` | a number | add 1, with a scan and not a loop |
| `ADD` `SUB` | `(x,y)` | the sum or the difference |
| `MUL` | `(x,y)` | the product, with one addition for each bit of `y` |
| `MULS` | `(x,y)` | the same product, with one addition for each unit of `y` |
| `FACT` `FACTS` | a number | the factorial, with `MUL` or with `MULS` |

### How a program moves data

A split cannot move data from one half of the cube to the other half. But
`NAND(NOT L, TRUE)` is `L`. Therefore a program can project one half:

    LEFT  := @(NOT,TRUE)
    RIGHT := @(TRUE,NOT)

The pattern `(F,G)=` then builds a new cube from two functions of the
complete input. The `=` gives a copy of the cube to `F` and to `G`. With
`LEFT`, `RIGHT` and this pattern, a program can compute any function of the
cube. The recursion of a block gives divide and conquer over the tree of the
cube. `SHLIN` and `PA` use this method.

### How a loop stops

Each loop uses this pattern:

    @( @(COND,THEN)= , @(NOTCOND,ELSE)= )=

This is a choice between `THEN` and `ELSE`. `COND` and `NOTCOND` must give
the same bit at every position.

If `COND` is false everywhere, the lazy rule skips `THEN`. `THEN` holds the
recursive call, so the loop stops. A failure is not necessary. If `COND` is
true everywhere, `NOTCOND` is false everywhere, and the lazy rule skips
`ELSE`.

`ADD` uses the classic carry loop. The state is the cube `(x,c)`:

    while c is not zero:  x, c := x XOR c, (x AND c) moved one place up

The carry moves one place up at each step, so the loop always stops. `INC`
is `ADD` with the number 1, and `MULS` adds `x` and calls itself with `y-1`.

### The two multiplication programs

`MUL` is the usual product program. It makes one addition for each bit of
`y`:

    x * y = (x AND the low bit of y) + (2x * (y / 2))

`MULS` is the simple method. The S is for slow: it makes one addition for
each unit of `y`:

    x * y = x + (x * (y - 1))

`FACT` uses `MUL`, and `FACTS` uses `MULS`. The programs give the same
results. `python bench.py 4 7` measures the two programs. The table below
gives one measurement with a cube of 4 inds, which holds 16 bits. The column
"nands" gives the number of `@` operations, so this number does not depend on
the computer.

| x | x! | FACTS ms | FACTS nands | FACT ms | FACT nands | faster |
|---|----|---------|------------|----------|-------------|--------|
| 4 | 24 | 17 | 24683 | 15 | 17187 | 1.1x |
| 5 | 120 | 86 | 101277 | 22 | 27698 | 3.9x |
| 6 | 720 | 438 | 506647 | 34 | 45691 | 12.7x |
| 7 | 5040 | 2614 | 3235326 | 67 | 69840 | 39.0x |

The number 7! is 5040, and 5040 needs 13 bits. A cube holds a power of 2 bits,
so the cube for 7! must hold 16 bits.

`MUL` is not faster for a small `y`. Each step of `MUL` also makes a shift
up, a shift down and an AND. Therefore one step of `MUL` costs more than one
step of `MULS`. `MUL` becomes faster when `y` is larger than the number of
bits. The table shows this change at 4! = 24.

For one multiplication the difference is larger, because `FACTS` also makes
small multiplications:

| case | MULS nands | MUL nands |
|------|-----------|------------|
| 7 * 24 | 87419 | 11031 |
| 7 * 120 | 450068 | 18504 |
| 7 * 720 | 2727907 | 23377 |
| 255 * 255 | 1205164 | 35476 |

## Input and output

A source file that starts with the line `IO` uses the IO interface. The
interpreter then runs the program many times. The first cube is one false
bit, with 0 inds. Each result tells the interpreter what to do next:

| Result | Meaning |
|--------|---------|
| `(0,x)` | The program is complete. `x` is the return value. |
| `(1,(0,y))` | Read one byte. The program starts again with `(1,(byte,y))`. |
| `(1,((1,a),y))` | Write the 8 low bits of `a`. The program starts again with `(1,y)`. |

The first half of the result must hold only true bits or only false bits.

A byte from a read has zeros above the 8 low bits. Therefore the cube for
`x` in a read request needs 3 inds or more. At the end of the input the
interpreter gives a cube with bit 8 true and all other bits false. A program
can test the high half of the byte cube to find the end of the input.

### The shapes

The number of inds of the next cube tells the program what happened:

* A read request `(1,(x,y))` with `n` inds gives back a cube with `n` inds.
* A write request `(1,(x,y))` with `n` inds gives back a cube with `n-1`
  inds, because the request part `x` is gone.
* The first cube has 0 inds.

A program can therefore find its case with a probe. The program `(X,)` gives
the same result as `X`, but it needs one ind more. So a chain of probes in
the handlers of a block selects the case:

    MAIN := [ AFTERREAD P6 , [ AFTERWRITE P5 , START ] ]

### The demonstrations

`examples/cat.hc` copies stdin to stdout. It reads a byte, writes the byte,
and stops at the end of the input.

    ./hypercube examples/prelude.hc examples/arith.hc examples/cat.hc < file

`examples/bf.hc` is an interpreter for Brainfuck, and `examples/bfu.hc` is
the same interpreter with a memory of no fixed size; see "The Brainfuck
interpreter" and "Memory of no fixed size" below.

`examples/bottles.hc` writes the ninety-nine bottles of beer song. The file
is the output of `python mkbottles.py`. The song is 11886 bytes, and the
program needs about 8 seconds and 21 million `@` operations.

    ./hypercube examples/prelude.hc examples/arith.hc examples/bottles.hc

The state of the song program is a cube with 5 inds: the position in a
template of 512 bytes, and two decimal digits for the counter. Two decimal
digits are simpler than a division by 10.

The program reads one byte of the template at each step. Eight byte values
are markers: write a digit, write the letter s, subtract 1 from the counter,
go to another position, or stop. A marker changes the state, and the program
then calls itself. The generator writes the template as a tree of choices on
the 9 bits of the position. The lazy rule of `@` runs only one path of that
tree, so a lookup costs about 9 steps and not 512.

## The Brainfuck interpreter

`examples/bf.hc` is an interpreter for Brainfuck. It reads stdin up to the
first new line. That text is the Brainfuck program. The interpreter then
runs it. A `.` goes to stdout at once, and a `,` reads one more byte of
stdin.

    echo '++++++++[>++++++++<-]>+.' | ./hypercube examples/prelude.hc \
        examples/arith.hc examples/mem.hc examples/bf.hc
    A

The program below writes the letter A without end. The output comes out
byte by byte, so a program that never stops is still useful:

    echo '++++++++[>++++++++<-]>+[.]' | ./hypercube examples/prelude.hc \
        examples/arith.hc examples/mem.hc examples/bf.hc

### The state

The whole machine is one cube with 11 inds:

    state = ( PROG(10) , ( TAPE(9) , ( ( IPM(7) , TPM(7) ) , ( MODE(7) , DEP(7) ) ) ) )

`PROG` holds 128 bytes and `TAPE` holds 64 cells of 8 bits. `MODE` says
what the machine does now: load the program, run it, or walk over a loop
forward or back. `DEP` counts the depth of the brackets.

### A pointer is a mask, not a number

`IPM` and `TPM` are one-hot masks: the position of the true bit is the
position of the pointer. This choice makes the whole interpreter simple:

* A step of a pointer is `SHL1` or `SHR1` of the mask. No arithmetic and no
  comparison are necessary.
* `STR3` makes each bit of a mask into 8 equal bits. The mask then has the
  same shape as the block of bytes, and both halve together. `SELB` walks
  down the two cubes and stops where the mask holds only true bits. That
  place is the byte. `STB` writes a byte in the same manner.
* The test "is the pointer off the end" is `NOT ORR IPM`.

`SHL1` moves the one true bit of a mask. It needs one recursive call at
each level, because only one half of the cube holds the bit. `SHL` works
for any cube and needs two calls at each level. For a mask of 128 bits
`SHL` costs 21250 program parts and `SHL1` costs 2000. This one change made
the interpreter 3 times faster.

`MODE` and `DEP` are one-hot too, so a change of mode is also a shift.

### Two loops

`LOOP` runs Brainfuck steps one after the other. It stops only at a step
that needs the driver: a `.`, a `,`, the end of the program, or the load
mode. Therefore the interpreter makes many Brainfuck steps for one request,
and the large cube of a request (13 inds) is necessary one time for each
byte of output only. `LOOP` carries the pair (byte at the pointer, state),
so it reads the program one time for each step.

### Limits

* The Brainfuck program must have 128 bytes or less, and the tape has 64
  cells. `examples/bfu.hc` removes both limits; see "Memory of no fixed
  size".
* A `,` at the end of the input gives the byte 0.
* Between two bytes of output the interpreter can make about 40000
  Brainfuck steps. After that it stops at the call depth limit. Use
  `--max-depth 500000` for more.
* Hello World needs about 4 seconds.

`python tests_bf.py` compares the interpreter with a Brainfuck interpreter
in python, for 11 programs.

## Memory of no fixed size, and Turing completeness

`examples/bf.hc` above has a memory of fixed size: 128 bytes of program and
64 cells. `examples/bfu.hc` is the same interpreter without that limit. It
starts with 32 bytes of program and 16 cells, and it makes the memory two
times larger every time the memory is full.

    echo '++++++++[>++++++++<-]>+.' | ./hypercube examples/prelude.hc \
        examples/arith.hc examples/mem.hc examples/bfu.hc

A program can therefore run with the memory that it needs, and hypercube is
Turing complete.

### The memory becomes larger

`=` gives a cube of one ind more, so a program can make its own memory
larger. The program `(,FALSE)=` doubles a cube and puts the old bits in the
low half, so every bit keeps its position:

    ./hypercube examples/prelude.hc examples/arith.hc -e '(,FALSE)=' -i 1101
    inds=3 bits=11010000

`GROW` does this to every part of the state at the same time, so the shape
of the state stays correct. The one-hot masks grow with the blocks, and a
mask keeps its position, so nothing else must change.

The state doubles while a program of 40 bytes loads:

    step 0    READ '+'   state=512 bits
    step 36   READ '+'   state=1024 bits
    step 41   WRITE "'"  state=2048 bits

### The two rules for a program of no fixed size

A program that works at every size must follow two rules. Both rules come
from the shape rules of the language.

**1. No fixed number of `=` operations.** `bf.hc` makes a test into a cube
of 11 inds with `=============`. That is not possible when the size of the
state changes. Every test must therefore keep the shape of the state:

    ANY AND ( , MASK )=

`MASK` is a state with true bits at one field only, and the same rebuild
that changes a field builds it. `AND` keeps the shape, and `ANY` gives the
answer of the test at every position, whatever the size is. For a test on a
byte, `BSEL` gives the byte at a mask at every byte of the block, and
`[=#LEFT Q4B,K]` gives a constant byte at every byte. The two cubes then
have the same shape, and `NOT ANY XOR` compares them.

**2. No test with `@` around a step that changes the size.** The two halves
of a split must have the same inds, so `@(C,A)=` needs `A` and `C` of one
size. A block does not compare its two parts:

    [ A KEEP , B ]

`A` and `B` may give cubes of different sizes. `KEEP` gives the cube again
if a test is true, and fails if it is false:

    KEEP := AND ( , @( TEST , FAILB )= )=
    FAILB := @ ANDR          ; this program always fails

The lazy rule of `@` skips `FAILB` when `TEST` is false everywhere, so no
failure happens. When `TEST` has a true bit, `FAILB` runs and fails, and the
handler of the block takes the other part. This is a test on the bits that
gives results of different shapes. `bfu.hc` uses it for the loop, for the
choice between the requests, and for every step that makes the memory
larger.

### What it costs

| | `bf.hc` | `bfu.hc` |
|---|---|---|
| program | 128 bytes | no limit |
| tape | 64 cells | no limit |
| Hello World | 3.8 s | 9.6 s |

The tests below show the difference. The first program has 201 bytes and the
second uses cell 100:

| program | `bf.hc` | `bfu.hc` | python |
|---------|---------|----------|--------|
| 200 `+` then `.` | fatal error | `\xc8` | `\xc8` |
| 100 `>` then 65 `+` then `.` | fatal error | `A` | `A` |

`bfu.hc` runs a program of 666 bytes that uses cell 600 in 17 seconds. The
only limits that are left are the two safety limits of the interpreter:
`--max-inds` (the size of a cube, 24 by default) and `--max-depth`. Both are
limits of this C++ program, not of the language.

`python tests_bf.py examples/bfu.hc` runs the 13 test programs against the
interpreter that grows.

## One program without names

`--expand` gives the program again with every name replaced by its body. The
result holds no names at all. Every character of the language is one token,
so the result needs no space between the parts:

    ./hypercube examples/prelude.hc -e 'TRUE' --expand
    @(@=,)=

`make nameless` writes the three large programs to the `nameless` directory.
Each file is one line of `IO`, and then one expression:

| file | characters |
|------|------------|
| `nameless/bf-nameless.txt` | 182 615 |
| `nameless/bottles-nameless.txt` | 277 491 |
| `nameless/bfu-nameless.txt` | 439 411 |

Each file runs alone, with no library:

    printf '++++++++[>++++++++<-]>+.\n' | ./hypercube nameless/bf-nameless.txt
    A

The expander gives the size first, and stops if the size is over the limit of
`--max-expand` (64 million characters). It computes that size from the tree
without building the text, so a program that would give gigabytes stops at
once.

### Why the substitution is safe

A `#` counts brackets, not definitions, and the parser rejects a `#` in a
definition that has no brackets of its own. Therefore every `#` in a body is
already bound inside that body, and no substitution can catch it. The number
of ampersands never changes.

### A name may not call itself through the names

    ./hypercube -e 'F := @ G' -e 'G := @ F' -e 'F' --expand
    source error: the name F calls itself through the names, so the program
    cannot expand; use # for that loop

A loop must therefore use `#` and a block. This is also the style of the
programs here: **no name in `examples/` refers to itself.** `SELB` shows the
form. The extra `[ , ]` gives the `#` a block to name:

    SELB := [@(@(ATB,LEFT)=,@(NATB,@(@(GOL,# LPR)=,@(NGOL,# RPR)=)=)=)=,]

A block with an empty handler catches a failure and gives the cube again. For
a failure that must pass to the level above, put a program that always fails
in the handler:

    [ X , @[#@,] ]

`[#@,]` applies `@` until no ind is left, and the `@` in front of it then
fails.

None of the three expanded programs holds a single `&`. Every loop in this
library has one head, so the ampersand is never necessary.

## Notes on the semantics

The shape rules and the two operations do not settle every point. These are
the choices of this interpreter.

1. **A block without a handler does not catch.** Only a block with a comma
   catches a failure.
2. **The handler runs on the input of the block.** It does not run on the
   partial result at the point of the failure.
3. **A shape error is a normal failure.** A handler can catch it, in the same
   manner as a split of a cube with 0 inds.
4. **The scope of `#` is lexical.** The interpreter finds the block of a `#`
   at parse time. A `#` inside a definition cannot refer to a block outside
   that definition.
5. **The level of the lazy rule.** The section "Lazy evaluation" gives the
   list of the forms. A deeper analysis is possible, but it is not necessary
   for the minimal behaviour. Note also: the lazy rule skips the right part,
   so the interpreter cannot know the shape of that part. With `--pad`, the
   result of a skipped part takes the shape of the left part.
6. **Input and output.** Without the IO header, the interpreter reads one
   cube of bits and prints one cube of bits.
7. **The syntax of a file.** The `;` comment, the end of a statement at the
   end of a line, and the rules for the entry point belong to this
   interpreter and not to the cube.
8. **No static check of the shapes.** The interpreter reports a shape error
   at run time only. A check at parse time is possible for a program without
   recursion.
9. **The end of the input.** A program needs a mark for it, so the
   interpreter sets bit 8 of the byte cube at the end of the input. If the byte cube holds 8 bits or less, the end of the input
   gives all false bits. Bit 8 is the low bit of the high half of a cube with
   16 bits, so the test is short.
10. **The IO header.** The interpreter takes the first line that is not blank
   and not a comment. If that line is `IO`, the file uses the IO interface.
   Every file and every `-e` text can hold the header. The option `--no-io`
   ignores the header, which helps a test of one definition. The option `-i`
   has no effect for an IO program.
11. **A short write.** If the cube `a` in a write request holds less than 8
   bits, the missing high bits are false.
12. **A name is not a macro.** The interpreter looks up a name when it runs,
   so two names may call each other. A version that expands the names as text
   cannot do that, and every loop must then use `#`. The programs here use
   `#` for every loop, so they run under both rules. `--expand` reports a
   loop through the names, because such a program has no end as text.
