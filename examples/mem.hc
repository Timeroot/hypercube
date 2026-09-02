; mem.hc - a byte array in a cube, with a one-hot mask for the index.
; Use this file with prelude.hc and arith.hc.
;
; A block of 2^m bytes is a cube with m+3 inds. The index of a byte is a
; mask: a cube with m inds that holds one true bit. A step of the index is
; then SHL or SHR of the mask, and no arithmetic is necessary.
;
; STR3 makes the mask fit the block: it makes each bit of the mask into 8
; equal bits. The mask and the block then have the same number of inds, and
; both halve together at each step of the walk down the tree.

; ORR gives the OR of every bit, as a cube with 0 inds.
ORR := NOT ANDR NOT

; STR3 makes each bit into 8 equal bits.
STR3 := [(#,#),===]

; ------------------------------------------------------------------
; SELB - read one byte
; ------------------------------------------------------------------
; SELB takes a pair (block, mask). The mask is already stretched.
; The walk stops when the mask holds only true bits, because at that place
; the block is one byte.

SELB := [@(@(ATB,LEFT)=,@(NATB,@(@(GOL,# LPR)=,@(NGOL,# RPR)=)=)=)=,]

ATB   := === ANDR RIGHT
NATB  := === NOT ANDR RIGHT
GOL   := === ORR LEFT RIGHT
NGOL  := === NOT ORR LEFT RIGHT
LPR   := (LEFT LEFT,LEFT RIGHT)=
RPR   := (RIGHT LEFT,RIGHT RIGHT)=

; ------------------------------------------------------------------
; STB - write one byte
; ------------------------------------------------------------------
; STB takes ((block, mask), copies). The part "copies" holds the new byte
; many times, so that it halves together with the block.
; The result is the block with the new byte at the place of the mask.

STB := [@(@(SATB,LEFT RIGHT)=,@(SNATB,@(@(SGOL,(# SLARG,RIGHT LEFT LEFT)=)=,@(SNGOL,(LEFT LEFT LEFT,# SRARG)=)=)=)=)=,]

SATB  := ALL RIGHT LEFT
SNATB := NOT ALL RIGHT LEFT
SGOL  := = ANY LEFT RIGHT LEFT
SNGOL := = NOT ANY LEFT RIGHT LEFT

SLARG := ((LEFT LEFT LEFT,LEFT RIGHT LEFT)=,LEFT RIGHT)=
SRARG := ((RIGHT LEFT LEFT,RIGHT RIGHT LEFT)=,LEFT RIGHT)=

; ------------------------------------------------------------------
; SHL1 and SHR1 - move the one true bit of a mask
; ------------------------------------------------------------------
; SHL and SHR work for any cube, so they walk over every bit. A mask holds
; one true bit only. Therefore a step of a mask needs one recursive call at
; each level, and not two. SHL1 is about 60 times faster than SHL for a
; mask of 128 bits.
;
; SHL1((L,R)) = ( SHL1(L) , bit 0 if the true bit was at the top of L )
;               if the true bit is in L
; SHL1((L,R)) = ( 0 , SHL1(R) )   if the true bit is in R

TOPC := [(FALSE,#),TRUE]     ; a mask with the highest bit true

SHL1 := [@(@(CL1,(# LEFT,NRT)=)=,@(NCL1,(FALSE LEFT,# RIGHT)=)=)=,FALSE]
CL1  := = ANY LEFT
NCL1 := = NOT ANY LEFT
NRT  := @(@(MSBBC LEFT,ONEC LEFT)=,@(NOT MSBBC LEFT,FALSE LEFT)=)=

SHR1 := [@(@(CR1,(NLF,# RIGHT)=)=,@(NCR1,(# LEFT,FALSE RIGHT)=)=)=,FALSE]
CR1  := = ANY RIGHT
NCR1 := = NOT ANY RIGHT
NLF  := @(@(LSBBC RIGHT,TOPC RIGHT)=,@(NOT LSBBC RIGHT,FALSE RIGHT)=)=

; ------------------------------------------------------------------
; programs for a cube of any size
; ------------------------------------------------------------------
; The programs below need no fixed number of = operations. Therefore a
; program can use them when the size of the state is not known, and the
; state can become larger while the program runs.

FSTB := [#LEFT Q4B,]      ; the first byte of a cube
REPB := [=#LEFT Q4B,]     ; byte 0 of the cube, at every byte
INC0 := [(#,)Q4B,INCP]    ; add 1 to byte 0 only
DEC0 := [(#,)Q4B,DECP]    ; take 1 from byte 0 only
Q4B  := ((((,),),),)      ; a probe: this program needs 4 inds

; FAILB always fails. With the lazy rule of @ it gives a test that depends
; on the bits: @(C,FAILB)= fails if C holds a true bit, and gives true bits
; if C is false everywhere.
FAILB := @ ANDR

; KEEP gives the cube again if C is false everywhere, and fails if not.
; The block [ A KEEP , B ] is therefore a choice between A and B, and A and
; B may give cubes of a different size. A test with @ cannot do that.

; BSEL takes a pair (block, mask) like SELB. It gives the byte at the mask,
; but at every byte of the block. The byte comes back at the size of the
; block, so no fixed number of = operations is necessary.
BSEL := [@(@(BATB,LEFT)=,@(BNATB,= @(@(BGOL,# LPR)=,@(BNGOL,# RPR)=)=)=)=,]
BATB  := ALL RIGHT
BNATB := NOT ALL RIGHT
BGOL  := ANY LEFT RIGHT
BNGOL := NOT ANY LEFT RIGHT
