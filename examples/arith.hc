; arith.hc - binary arithmetic on a cube.
; Use this file with prelude.hc:
;   hypercube examples/prelude.hc examples/arith.hc --entry ADD -i 11001010
;
; --- the number format ---
; A cube with n inds holds a number of 2^n bits. The bit at flat index i has
; the place value 2^i. The first ind is the highest bit of the address.
; Therefore the left half of a cube holds the low bits of the number, and
; the right half holds the high bits.
; The interpreter prints the low bit first. The 4-bit number 3 is 1100.
; All operations work modulo 2^(2^n). The high bits fall off the cube.
;
; --- the two-number format ---
; ADD, SUB, MUL and MULS take a cube with the shape (x,y). This cube has one
; ind more than the numbers x and y. The result has the same inds as x.

; ------------------------------------------------------------------
; projections
; ------------------------------------------------------------------
; A split cannot move data from one half to the other half. But a program
; can project one half of the cube, because NAND(NOT L, TRUE) is L.
; With LEFT and RIGHT, the pattern (F,G)= builds a new cube from two
; functions of the complete input.

LEFT  := @(NOT,TRUE)     ; n -> n-1 : the low half
RIGHT := @(TRUE,NOT)     ; n -> n-1 : the high half

; ------------------------------------------------------------------
; constants and single bits
; ------------------------------------------------------------------

; MSBBC gives the highest bit of the cube at every position.
MSBBC := [=#RIGHT,]

; ONEC is the number 1: one true bit at the flat index 0.
ONEC  := [(#,FALSE),TRUE]

; ------------------------------------------------------------------
; the shift
; ------------------------------------------------------------------
; SHLIN takes a cube with the shape (x,c). The cube c holds the carry bit
; at every position. SHLIN moves x one place up and puts the carry bit at
; the flat index 0. The highest bit of x falls off.
;
; The recursion is:
;   SHLIN((L,R), c) = ( SHLIN(L, c) , SHLIN(R, top bit of L) )
; The block catches the failure of LEFT at 0 inds. The handler then
; returns the carry bit.

SHLIN := [(#(LEFT LEFT,LEFT RIGHT)=,#(RIGHT LEFT,MSBBC LEFT LEFT)=)=,RIGHT]

; SHL moves a number one place up. This multiplies the number by 2.
SHL := SHLIN (,FALSE)=

; SHRIN is the same operation in the other direction. It puts the carry bit
; at the highest place. The recursion is:
;   SHRIN((L,R), c) = ( SHRIN(L, low bit of R) , SHRIN(R, c) )
; LSBBC gives the lowest bit of the cube at every position.

LSBBC := [=#LEFT,]
SHRIN := [(#(LEFT LEFT,LSBBC RIGHT LEFT)=,#(RIGHT LEFT,RIGHT RIGHT)=)=,RIGHT]

; SHR moves a number one place down. This divides the number by 2.
SHR := SHRIN (,FALSE)=

; ------------------------------------------------------------------
; the loop pattern
; ------------------------------------------------------------------
; Each loop below has this shape:
;   @( @(COND,THEN)= , @(NOTCOND,ELSE)= )=
; This is a choice between THEN and ELSE. The programs COND and NOTCOND
; give the same bit at every position.
; If COND is false everywhere, the lazy rule of @ skips THEN. THEN holds
; the recursive call, so the loop stops. No failure is necessary.

; ------------------------------------------------------------------
; ADD and SUB
; ------------------------------------------------------------------
; ADD is the classic carry loop. The state is the cube (x,c):
;   while c is not zero:  x, c := x XOR c, (x AND c) moved one place up
; The carry moves up at each step. After 2^n steps the carry is zero.

ADD := [@(@(ANY RIGHT,#(XOR,SHL AND)=)=,@(EQ0 RIGHT,LEFT)=)=]

; SUB uses the same loop with a borrow. The borrow is (NOT x AND y).
SUB := [@(@(ANY RIGHT,#(XOR,SHL AND(NOT LEFT,RIGHT)=)=)=,@(EQ0 RIGHT,LEFT)=)=]

; ------------------------------------------------------------------
; INC and DEC
; ------------------------------------------------------------------
; INC adds the number 1. The loop of ADD then carries the 1 up through the
; bits, and stops when no carry is left.

INC := ADD (,ONEC)=
DEC := SUB (,ONEC)=

; INCP is a second increment program. It does not loop over the carry.
; It uses this rule: bit i of x+1 is different from bit i of x if, and
; only if, every bit below i is true.
; PA gives that test at each position. PA is the prefix AND of the cube:
;   PA((L,R)) = ( PA(L) , PA(R) AND (the AND of all of L) )
; The recursion divides the cube, so the number of steps is n, not 2^n.

PA   := [(#LEFT,AND(#RIGHT,ALL LEFT)=)=,TRUE]
INCP := XOR (,PA)=

; DECP takes 1 away in the same manner. Bit i of x-1 is different from
; bit i of x if, and only if, every bit below i is false.
DECP := XOR (,PA NOT)=

; ------------------------------------------------------------------
; MUL and MULS
; ------------------------------------------------------------------
; MUL is the usual product program. It looks at the low bit of y at each
; step:
;   x * y = 0                          if y is zero
;   x * y = (x AND low bit of y) + (2x * (y/2))
; The number y becomes smaller by one bit at each step. Therefore MUL makes
; one addition for each bit of y.

MUL := [@(@(ANY RIGHT,ADD(AND(LEFT,LSBBC RIGHT)=,#(SHL LEFT,SHR RIGHT)=)=)=,@(EQ0 RIGHT,FALSE LEFT)=)=]

; MULS is the simple method. The S is for slow: MULS makes one addition for
; each unit of y.
;   x * y = 0                  if y is zero
;   x * y = x + (x * (y - 1))  if y is not zero
; The lazy rule stops the recursion at y = 0.

MULS := [@(@(ANY RIGHT,ADD(LEFT,#(LEFT,DEC RIGHT)=)=)=,@(EQ0 RIGHT,FALSE LEFT)=)=]

; ------------------------------------------------------------------
; FACT and FACTS
; ------------------------------------------------------------------
; The factorial is:
;   fact(x) = 1                if x is zero
;   fact(x) = x * fact(x - 1)  if x is not zero
; FACT uses MUL. FACTS uses the slow MULS, for a comparison of the two
; product programs.
; The number 7! is 5040, so the cube must have 4 inds for 16 bits.

FACT  := [@(@(ANY,MUL(,#DEC)=)=,@(EQ0,ONEC)=)=]
FACTS := [@(@(ANY,MULS(,#DEC)=)=,@(EQ0,ONEC)=)=]
