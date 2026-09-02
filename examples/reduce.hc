; reduce.hc - programs that use a block to loop over the inds.
; Use this file with prelude.hc:
;   hypercube examples/prelude.hc examples/reduce.hc -i 1011

; A reduce program has this shape:
;   [ = # GATE , ]
; The program applies GATE to the two halves. This removes one ind.
; Then the program calls itself. The cube becomes smaller at each step.
; The last call gets a cube with 0 inds, so GATE fails.
; The handler part is empty, so the failed call returns the single bit.
; Each level then applies = to the result. This sends the bit back
; to every position of the original cube.

PARITY := [=#XOR,]      ; true everywhere if the number of true bits is odd
ALLOF  := [=#AND,]       ; the same program as ALL in prelude.hc
ANYOF  := [=#OR,]        ; true everywhere if one bit or more is true

; EQ takes a cube with the shape (a,b). It returns true everywhere if
; a and b hold the same bits. The result has one ind less than the input.
EQ := ALL XNOR

MAIN := PARITY
