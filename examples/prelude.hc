; prelude.hc - basic programs.
; A program runs from right to left.
; A gate program takes a cube that has the shape (a,b) and returns one half.

; --- programs that keep the shape ---

ID    :=                  ; the empty program
ID2   := @=@=             ; NOT twice
ID4   := @@==             ; four copies, then two NAND steps

NOT   := @=               ; copy the cube, then NAND it with itself

; NAND(x, NOT x) is always true, so this program makes all bits true.
TRUE  := @(NOT,)=
FALSE := NOT TRUE

; --- gates on a cube with the shape (a,b) ---

NAND  := @
AND   := @=@
OR    := @(NOT,NOT)
NOR   := NOT OR
XOR   := AND (OR, NAND) =
XNOR  := NOT XOR

; --- the choice program ---
; IF takes a cube with the shape ((a,a),(b,c)) and returns b where a is
; true, and c where a is false. The result has two inds less than the input.
; The four NAND steps are the standard NAND multiplexer.

IF    := @@((,NOT),)

; --- programs that reduce the whole cube ---

; ANDR makes an AND of every bit. The result is a cube with 0 inds.
; A program can use ANDR to make a cube of any shape into one bit, and then
; build a constant from that bit.
ANDR  := [#@=@,]

; ALL makes an AND of every bit, then sends the result back to every bit.
; The block catches the failure of the last @, which has no ind left.
ALL   := [=#@=@,]

; EQ0 is true everywhere if every input bit is false.
EQ0   := ALL NOT
ANY   := NOT EQ0
