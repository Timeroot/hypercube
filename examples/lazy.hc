; lazy.hc - a demonstration of the lazy @ operation.
; Use this file with prelude.hc:
;   hypercube examples/prelude.hc examples/lazy.hc -i 1

; The block calls itself in the right part of the split.
; The recursion has no end condition.
; But the left part gives only false bits, and NAND(false, y) is true.
; So the interpreter does not run the right part, and the program stops.
;
; Steps for the input bit 1:
;   =            the cube becomes (1,1)
;   (NOT, #)     the left part becomes 0
;   @            the left part is all false, so # never runs
;   the result is the single bit 1

STOPS := [@(NOT,#)]=

; This program has the same parts in the other order. The left part is the
; recursive call, so the interpreter must run it. The cube loses one ind at
; each step. The call with 0 inds cannot split, and the program fails.
;
;   LOOPS := [@(#,NOT)]=

MAIN := STOPS
