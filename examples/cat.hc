IO
; cat.hc - copy stdin to stdout.
;   hypercube examples/prelude.hc examples/arith.hc examples/cat.hc < file
;
; The program has three cases. It knows the case from the number of inds:
;   0 inds : the start of the program        -> ask for a byte
;   6 inds : (1,(byte,y)) after a read       -> write the byte, or stop
;   5 inds : (1,y) after a write             -> ask for a byte
;
; A probe finds the number of inds. The program (X,) is the same as X, but
; it needs one ind more than X. Therefore P6 fails for a cube with 5 inds,
; and the handler of the block takes the next case.

P5 := (((((,),),),),)
P6 := ((((((,),),),),),)

; The read request is (1,(0,0)) with 6 inds. The parts x and y have 4 inds,
; so the byte comes back in a cube of 16 bits.
RREQ5 := (TRUE,FALSE)=             ; from a cube with 5 inds
RREQ0 := (=====TRUE,=====FALSE)=   ; from a cube with 0 inds

; After a read the cube is (1,(B,y)). B has 16 bits: the byte is in the low
; 8 bits. At the end of the input, bit 8 is true. Therefore the high half of
; B tells the program to stop.
BYTE  := LEFT RIGHT
ENDIN := === ANY RIGHT BYTE
MOREIN := === EQ0 RIGHT BYTE

; The write request is (1,((1,a),0)) with 6 inds. The part a has 8 bits.
WREQ := (TRUE LEFT,((TRUE,)= LEFT BYTE,FALSE BYTE)=)=

; A cube of false bits gives (0,x), so the program is complete.
STOP := FALSE

AFTERREAD := @(@(ENDIN,STOP)=,@(MOREIN,WREQ)=)=

MAIN := [AFTERREAD P6,[RREQ5 P5,RREQ0]]
