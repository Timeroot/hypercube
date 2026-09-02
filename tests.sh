#!/bin/sh
# tests.sh - run the checks. Use: sh tests.sh
HC=./hypercube.exe
LIB="examples/prelude.hc examples/arith.hc"
pass=0
fail=0

# ok NAME EXPECTED INPUT PROGRAM [extra args]
ok() {
  name=$1; want=$2; in=$3; prog=$4; shift 4
  got=$("$HC" $LIB -e "$prog" -i "$in" --raw "$@" 2>&1)
  if [ "$got" = "$want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: program [$prog] input [$in]"
    echo "     want [$want] got [$got]"
  fi
}

# err NAME EXITCODE INPUT PROGRAM
err() {
  name=$1; want=$2; in=$3; prog=$4
  "$HC" $LIB -e "$prog" -i "$in" --raw >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: program [$prog] want exit $want got exit $got"
  fi
}

# syn NAME EXITCODE PROGRAM
syn() {
  name=$1; want=$2; prog=$3
  "$HC" $LIB -e "$prog" --parse-only >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: program [$prog] want exit $want got exit $got"
  fi
}

# ioc NAME EXPECTED STDIN -- run cat.hc with the given input
ioc() {
  name=$1; want=$2; in=$3
  got=$(printf '%s' "$in" | "$HC" $LIB examples/cat.hc 2>&1)
  if [ "$got" = "$want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: want [$want] got [$got]"
  fi
}

# bf NAME EXPECTED PROGRAM STDIN -- run a Brainfuck program
bf() {
  name=$1; want=$2; prog=$3; data=$4
  got=$(printf '%s
%s' "$prog" "$data" | "$HC" $LIB examples/mem.hc examples/bf.hc 2>&1)
  if [ "$got" = "$want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: program [$prog] want [$want] got [$got]"
  fi
}

# bfu NAME EXPECTED PROGRAM STDIN -- run under the interpreter that grows
bfu() {
  name=$1; want=$2; prog=$3; data=$4
  got=$(printf '%s
%s' "$prog" "$data" | "$HC" $LIB examples/mem.hc examples/bfu.hc 2>&1)
  if [ "$got" = "$want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: want [$want] got [$got]"
  fi
}

echo "-- the two operations --"
ok "dup"        1010 10 '='
ok "nand"       0    11 '@'
ok "nand2"      1    00 '@'
ok "nand3"      1    01 '@'
ok "nand-mixed" 01   1110 '@'

echo "-- identity programs --"
ok "empty"      1011 1011 'ID'
ok "notnot"     1011 1011 '@=@='
ok "four"       1011 1011 '@@=='
ok "id-name"    1011 1011 'ID4'

echo "-- constant programs --"
ok "not"        0100 1011 'NOT'
ok "true"       1111 1011 'TRUE'
ok "false"      0000 1011 'FALSE'
ok "true-raw"   1111 1011 '@(@=,)='

echo "-- gates on (a,b) --"
ok "and-1001"   00 1001 'AND'
ok "and-1101"   01 1101 'AND'
ok "or-1001"    11 1001 'OR'
ok "or-0000"    00 0000 'OR'
ok "nand-1101"  10 1101 'NAND'
ok "nor-1001"   00 1001 'NOR'
ok "xor-1001"   11 1001 'XOR'
ok "xor-1010"   00 1010 'XOR'
ok "xor-1101"   10 1101 'XOR'
ok "xnor-1101"  01 1101 'XNOR'

echo "-- the choice program --"
# the input shape is ((a,a),(b,c)) with one bit in each part
ok "if-1-0-0"   0 1100 'IF'
ok "if-1-1-0"   1 1110 'IF'
ok "if-1-0-1"   0 1101 'IF'
ok "if-0-1-0"   0 0010 'IF'
ok "if-0-0-1"   1 0001 'IF'
ok "if-0-1-1"   1 0011 'IF'
# a, b and c each hold two bits: a=(1,0) b=(1,1) c=(0,0)
ok "if-wide"    10 10101100 'IF'

echo "-- whole cube programs --"
ok "all-1111"   1111 1111 'ALL'
ok "all-1101"   0000 1101 'ALL'
ok "all-1bit"   1    1    'ALL'
ok "eq0-0000"   1111 0000 'EQ0'
ok "eq0-0010"   0000 0010 'EQ0'
ok "eq0-0"      1    0    'EQ0'
ok "any-0000"   0000 0000 'ANY'
ok "any-0010"   1111 0010 'ANY'

echo "-- lazy evaluation --"
# the left half is all false, so the right half never runs
ok "lazy-stop"  1 1 '[@(@=,#)]='
ok "lazy-wide"  11 11 '[@(@=,#)]='
# the same program with the parts in the other order does not stop
err "eager-fail" 1 1 '[@(#,@=)]='

echo "-- failures and handlers --"
err "split-1bit" 1 1 '(,)'
err "nand-1bit"  1 1 '@'
err "bad-shape"  1 10 '(=,)'
ok  "pad-shape"  1100 10 '(=,)' --pad
ok  "catch"      1 1 '[@,]'
ok  "catch-work" 0 1 '[@,@=]'

echo "-- source errors --"
err "no-block"   2 1 '@#='
err "deep-recur" 2 1 '@[(#&,)]='
err "unknown"    2 1 'NOPE'
err "unbalanced" 2 1 '(@,'

echo "-- deep syntax --"
syn "deep-scopes" 0 '@=[@(#,[@=(#&,[(#&&,#)=])])=]'
syn "two-blocks"  0 '[[(#,#&)]]'
syn "amp-too-far" 2 '[[(#,#&&)]]'

echo "-- projections --"
ok "left"       10   1011 'LEFT'
ok "right"      11   1011 'RIGHT'
ok "msbbc-0"    0000 1000 'MSBBC'
ok "msbbc-1"    1111 0001 'MSBBC'
ok "onec"       1000 0000 'ONEC'
ok "onec-8"     10000000 00000000 'ONEC'

echo "-- shift: the low bit comes first --"
ok "shl-1"      0100 1000 'SHL'
ok "shl-2"      0010 0100 'SHL'
ok "shl-8"      0000 0001 'SHL'
ok "shl-11"     0110 1101 'SHL'
ok "shl-1bit"   0    1    'SHL'

echo "-- INC and DEC (4 bits) --"
ok "inc-0"      1000 0000 'INC'
ok "inc-3"      0010 1100 'INC'
ok "inc-15"     0000 1111 'INC'
ok "incp-3"     0010 1100 'INCP'
ok "incp-15"    0000 1111 'INCP'
ok "dec-0"      1111 0000 'DEC'
ok "dec-8"      1110 0001 'DEC'

echo "-- ADD and SUB (4 bits, x then y) --"
ok "add-3-5"    0001 11001010 'ADD'
ok "add-9-14"   1110 10010111 'ADD'
ok "add-0-0"    0000 00000000 'ADD'
ok "add-15-1"   0000 11111000 'ADD'
ok "sub-5-3"    0100 10101100 'SUB'
ok "sub-3-5"    0111 11001010 'SUB'
ok "sub-0-1"    1111 00001000 'SUB'

echo "-- MULS, one addition for each unit (4 bits) --"
ok "muls-3-5"    1111 11001010 'MULS'
ok "muls-7-2"    0111 11100100 'MULS'
ok "muls-0-9"    0000 00001001 'MULS'
ok "muls-9-0"    0000 10010000 'MULS'
ok "muls-4-4"    0000 00100010 'MULS'
ok "muls-1-13"   1011 10001011 'MULS'

echo "-- 8 bit arithmetic --"
ok "add-8bit"   10000000 1010110100110010 'ADD'
ok "muls-8bit"   00110110 0011000010010000 'MULS'

echo "-- shift down (4 bits) --"
ok "shr-1 "      0000 1000 'SHR'
ok "shr-2 "      1000 0100 'SHR'
ok "shr-4 "      0100 0010 'SHR'
ok "shr-8 "      0010 0001 'SHR'
ok "shr-11"      1010 1101 'SHR'

echo "-- MUL, one addition for each bit (4 bits) --"
ok "mul-3-5"  1111 11001010 'MUL'
ok "mul-7-2"  0111 11100100 'MUL'
ok "mul-0-9"  0000 00001001 'MUL'
ok "mul-9-0"  0000 10010000 'MUL'
ok "mul-4-4"  0000 00100010 'MUL'
ok "mul-13-5" 1000 10111010 'MUL'
ok "mul-15-15" 1000 11111111 'MUL'

echo "-- factorial (16 bits) --"
ok "facts-0"     1000000000000000 0000000000000000 'FACTS'
ok "facts-1"     1000000000000000 1000000000000000 'FACTS'
ok "facts-2"     0100000000000000 0100000000000000 'FACTS'
ok "facts-3"     0110000000000000 1100000000000000 'FACTS'
ok "facts-4"     0001100000000000 0010000000000000 'FACTS'
ok "facts-5"     0001111000000000 1010000000000000 'FACTS'
ok "fact-0"    1000000000000000 0000000000000000 'FACT'
ok "fact-1"    1000000000000000 1000000000000000 'FACT'
ok "fact-2"    0100000000000000 0100000000000000 'FACT'
ok "fact-3"    0110000000000000 1100000000000000 'FACT'
ok "fact-4"    0001100000000000 0010000000000000 'FACT'
ok "fact-5"    0001111000000000 1010000000000000 'FACT'
ok "fact-6"    0000101101000000 0110000000000000 'FACT'
ok "fact-7"    0000110111001000 1110000000000000 'FACT'

echo "-- the two MULS programs agree (16 bits) --"
ok "mul16-7-24"    0001010100000000 11100000000000000001100000000000 'MUL'
ok "mul16-12-9"    0011011000000000 00110000000000001001000000000000 'MUL'
ok "mul16-255-255" 1000000001111111 11111111000000001111111100000000 'MUL'

echo "-- the IO interface --"
ioc "cat-text"  "hello, hypercube!" "hello, hypercube!"
ioc "cat-empty" "" ""
ioc "cat-punct" "a,b;c()[]#&@=" "a,b;c()[]#&@="

# the song: check the size and the first and last lines
song=$("$HC" $LIB examples/bottles.hc)
n=$(printf '%s' "$song" | wc -c | tr -d ' ')
if [ "$n" = "11884" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL bottles-size: want 11884 got $n"
fi
first=$(printf '%s' "$song" | head -1)
if [ "$first" = "99 bottles of beer on the wall, 99 bottles of beer." ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL bottles-first: got [$first]"
fi
last=$(printf '%s' "$song" | tail -1)
if [ "$last" = "Go to the store and buy some more, 99 bottles of beer on the wall." ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL bottles-last: got [$last]"
fi

echo "-- the Brainfuck interpreter --"
bf "bf-A"      "A"      "++++++++[>++++++++<-]>+." ""
bf "bf-cat"    "hi!"    ",[.,]" "hi!"
bf "bf-echo"   "Z"      ",." "Z"
bf "bf-empty"  ""       ",[.,]" ""
bf "bf-skip"   "!"      "+++++++++++++++++++++++++++++++++[>++<-]>[-]<[->++<]>+++++++++++++++++++++++++++++++++." ""
bf "bf-hello"  "Hello World!" "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++." ""

echo "-- the Brainfuck interpreter that grows its memory --"
bfu "bfu-A"     "A"   "++++++++[>++++++++<-]>+." ""
bfu "bfu-cat"   "hi!" ",[.,]" "hi!"
# the program is longer than the first store of 32 bytes, so it must grow
bfu "bfu-grow-prog" "!" "+++++++++++++++++++++++++++++++++." ""
# cell 20 is past the first tape of 16 cells, so the tape must grow
bfu "bfu-grow-tape" "!" ">>>>>>>>>>>>>>>>>>>>+++++++++++++++++++++++++++++++++." ""

echo "-- the expander: one program without names --"
got=$(./hypercube.exe examples/prelude.hc -e 'TRUE' --expand 2>/dev/null)
if [ "$got" = "@(@=,)=" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL expand-true: got [$got]"; fi

got=$(./hypercube.exe examples/prelude.hc examples/arith.hc -e 'INCP' --expand 2>/dev/null | tr -cd 'A-Za-z' | wc -c | tr -d ' ')
if [ "$got" = "0" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL expand-nameless: $got letters left"; fi

# a loop through the names cannot expand, and the interpreter says so
./hypercube.exe -e 'F := @ G' -e 'G := @ F' -e 'F' --expand >/dev/null 2>&1
if [ $? = 2 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL expand-cycle: no error"; fi

# the file without names runs the same as the library version
got=$(printf '++++++++[>++++++++<-]>+.
' | ./hypercube.exe nameless/bf-nameless.txt 2>&1)
if [ "$got" = "A" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL nameless-bf: got [$got]"; fi
got=$(printf ',[.,]
hi!' | ./hypercube.exe nameless/bfu-nameless.txt 2>&1)
if [ "$got" = "hi!" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL nameless-bfu: got [$got]"; fi

echo "-- results: $pass pass, $fail fail --"
[ "$fail" -eq 0 ]
