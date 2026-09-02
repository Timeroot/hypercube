IO
; bf.hc - a Brainfuck interpreter.
;
;   echo '++++++++[>++++++++<-]>+.' | hypercube examples/prelude.hc \
;        examples/arith.hc examples/mem.hc examples/bf.hc
;
; The program reads stdin up to the first new line. That text is the
; Brainfuck program. The interpreter then runs it. A "." goes to stdout at
; once, so a program that never stops still gives its output. A "," reads
; one more byte of stdin.
;
; --- the state ---
; The state is a cube with 11 inds:
;     state = ( PROG(10) , MEM(10) )
;     MEM   = ( TAPE(9) , REGS(9) )
;     REGS  = ( ( IPM(7) , TPM(7) ) , ( MODE(7) , DEP(7) ) )
; PROG holds 128 bytes and TAPE holds 64 cells of 8 bits.
; IPM and TPM are one-hot masks: the true bit gives the position. A step of
; a pointer is then SHL1 or SHR1, and no arithmetic is necessary.
; MODE is one-hot: bit 0 load, bit 1 run, bit 2 skip forward, bit 3 skip
; back. DEP is a one-hot counter for the depth of the brackets.
;
; --- the two loops ---
; LOOP runs many Brainfuck steps for one request. It stops only at a step
; that needs the driver: a ".", a ",", the end of the program, or the load
; mode. LOOP works on a pair (byte at the pointer, state), so it reads the
; program one time for each step. The parts of the pair have 11 inds, and
; the request has 13 inds. Therefore the work of a step is small, and the
; large cube of a request is necessary one time for each byte of output.
;
; --- the interface ---
; A read request and a write request both have 13 inds. After a read the
; cube has 13 inds, and after a write it has 12 inds. The first cube has 0
; inds. The probes Q13 and Q12 find the case.

; ------------------------------------------------------------------
; probes and helpers
; ------------------------------------------------------------------
Q1  := (,)
Q2  := (Q1,)
Q3  := (Q2,)
Q4  := (Q3,)
Q5  := (Q4,)
Q6  := (Q5,)
Q7  := (Q6,)
Q8  := (Q7,)
Q9  := (Q8,)
Q10 := (Q9,)
Q11 := (Q10,)
Q12 := (Q11,)
Q13 := (Q12,)

B11 := ===========        ; make one bit into a cube with 11 inds
B12 := ============
B13 := =============
P7  := =======            ; make a byte into a cube with 10 inds
P8  := ========           ; make a byte into a cube with 11 inds

; ------------------------------------------------------------------
; the characters of Brainfuck
; ------------------------------------------------------------------
KGT  := (((FALSE,TRUE)=,(TRUE,TRUE)=)=,((TRUE,TRUE)=,(FALSE,FALSE)=)=)= ANDR
KLT  := (((FALSE,FALSE)=,(TRUE,TRUE)=)=,((TRUE,TRUE)=,(FALSE,FALSE)=)=)= ANDR
KPL  := (((TRUE,TRUE)=,(FALSE,TRUE)=)=,((FALSE,TRUE)=,(FALSE,FALSE)=)=)= ANDR
KMI  := (((TRUE,FALSE)=,(TRUE,TRUE)=)=,((FALSE,TRUE)=,(FALSE,FALSE)=)=)= ANDR
KDOT := (((FALSE,TRUE)=,(TRUE,TRUE)=)=,((FALSE,TRUE)=,(FALSE,FALSE)=)=)= ANDR
KCOM := (((FALSE,FALSE)=,(TRUE,TRUE)=)=,((FALSE,TRUE)=,(FALSE,FALSE)=)=)= ANDR
KOB  := (((TRUE,TRUE)=,(FALSE,TRUE)=)=,((TRUE,FALSE)=,(TRUE,FALSE)=)=)= ANDR
KCB  := (((TRUE,FALSE)=,(TRUE,TRUE)=)=,((TRUE,FALSE)=,(TRUE,FALSE)=)=)= ANDR
KNL  := (((FALSE,TRUE)=,(FALSE,TRUE)=)=,((FALSE,FALSE)=,(FALSE,FALSE)=)=)= ANDR

; ------------------------------------------------------------------
; the parts of the state
; ------------------------------------------------------------------
PROGF := LEFT
TAPEF := LEFT RIGHT
IPMF  := LEFT LEFT RIGHT RIGHT
TPMF  := RIGHT LEFT RIGHT RIGHT
MODEF := LEFT RIGHT RIGHT RIGHT
DEPF  := RIGHT RIGHT RIGHT RIGHT

; one bit of the one-hot fields
MLOAD := LEFT LEFT LEFT LEFT LEFT LEFT LEFT MODEF
MRUN  := RIGHT LEFT LEFT LEFT LEFT LEFT LEFT MODEF
MSKF  := LEFT RIGHT LEFT LEFT LEFT LEFT LEFT MODEF
MSKB  := RIGHT RIGHT LEFT LEFT LEFT LEFT LEFT MODEF
DZERO := LEFT LEFT LEFT LEFT LEFT LEFT LEFT DEPF

; the masks, stretched to the size of the block
PMASK := STR3 IPMF
TMASK := STR3 LEFT TPMF

; the byte at each pointer
INSTR := SELB (PROGF,PMASK)=
CELL  := SELB (TAPEF,TMASK)=

; the pointer is off the end of the program
IPZ0 := NOT ORR IPMF

; ------------------------------------------------------------------
; new states
; ------------------------------------------------------------------
; Each program below gives the state again, with one part changed.
; The shape of a state is ( PROG , ( TAPE , ( (IPM,TPM) , (MODE,DEP) ) ) ).

IPFWD  := (PROGF,(TAPEF,((SHL1 IPMF,TPMF)=,(MODEF,DEPF)=)=)=)=
IPBACK := (PROGF,(TAPEF,((SHR1 IPMF,TPMF)=,(MODEF,DEPF)=)=)=)=
TPFWD  := (PROGF,(TAPEF,((IPMF,SHL1 TPMF)=,(MODEF,DEPF)=)=)=)=
TPBACK := (PROGF,(TAPEF,((IPMF,SHR1 TPMF)=,(MODEF,DEPF)=)=)=)=
DEPUP  := (PROGF,(TAPEF,((IPMF,TPMF)=,(MODEF,SHL1 DEPF)=)=)=)=
DEPDN  := (PROGF,(TAPEF,((IPMF,TPMF)=,(MODEF,SHR1 DEPF)=)=)=)=
GORUN  := (PROGF,(TAPEF,((IPMF,TPMF)=,(SHL1 ONEC MODEF,DEPF)=)=)=)=
GOSKF  := (PROGF,(TAPEF,((IPMF,TPMF)=,(SHL1 SHL1 ONEC MODEF,ONEC DEPF)=)=)=)=
GOSKB  := (PROGF,(TAPEF,((IPMF,TPMF)=,(SHL1 SHL1 SHL1 ONEC MODEF,ONEC DEPF)=)=)=)=
CELLUP := (PROGF,(TINC,((IPMF,TPMF)=,(MODEF,DEPF)=)=)=)=
CELLDN := (PROGF,(TDEC,((IPMF,TPMF)=,(MODEF,DEPF)=)=)=)=

TINC := STB ((TAPEF,TMASK)=,P7 INCP CELL)=
TDEC := STB ((TAPEF,TMASK)=,P7 DECP CELL)=

; ------------------------------------------------------------------
; the pair (byte, state)
; ------------------------------------------------------------------
CH  := LEFT LEFT LEFT LEFT LEFT LEFT LEFT LEFT LEFT
ST  := RIGHT
MKP := (P8 INSTR,)=

; tests on the byte, as one bit
EDOT0 := ANDR XNOR (CH,KDOT)=
ECOM0 := ANDR XNOR (CH,KCOM)=
EZ0   := NOT ORR CH

; The driver is necessary at a ".", at a ",", at the end of the program,
; and in the load mode.
IOCH  := ORR ((EDOT0,ECOM0)=,(EZ0,EZ0)=)=
RUNIO := ANDR (MRUN ST,IOCH)=
STOP0 := ORR ((MLOAD ST,IPZ0 ST)=,(RUNIO,RUNIO)=)=

; ------------------------------------------------------------------
; the inner loop
; ------------------------------------------------------------------
LOOP := [@(@(SB,)=,@(NSB,# MKP NEXT)=)=]
SB   := B12 STOP0
NSB  := B12 NOT STOP0

; NEXT gives the state after one Brainfuck step. It never sees a ".", a ","
; or the end of the program, because LOOP stops at those.
NEXT := @(@(XSKF,SKFN)=,@(NXSKF,NX2)=)=
NX2  := @(@(XSKB,SKBN)=,@(NXSKB,RUNN)=)=

XSKF  := B11 MSKF ST
NXSKF := B11 NOT MSKF ST
XSKB  := B11 MSKB ST
NXSKB := B11 NOT MSKB ST

; ------------------------------------------------------------------
; the run mode
; ------------------------------------------------------------------
RUNN := @(@(XGT,TPFWD IPFWD ST)=,@(NXGT,V2)=)=
V2   := @(@(XLT,TPBACK IPFWD ST)=,@(NXLT,V3)=)=
V3   := @(@(XPL,IPFWD CELLUP ST)=,@(NXPL,V4)=)=
V4   := @(@(XMI,IPFWD CELLDN ST)=,@(NXMI,V5)=)=
V5   := @(@(XOB,OPENB)=,@(NXOB,V6)=)=
V6   := @(@(XCB,CLOSEB)=,@(NXCB,IPFWD ST)=)=

; "[" goes over the loop if the cell is 0. "]" goes back if it is not 0.
OPENB  := @(@(XCZ,IPFWD GOSKF ST)=,@(NXCZ,IPFWD ST)=)=
CLOSEB := @(@(NXCZ,IPBACK GOSKB ST)=,@(XCZ,IPFWD ST)=)=

; ------------------------------------------------------------------
; the skip modes
; ------------------------------------------------------------------
; The interpreter walks over the loop and counts the brackets. DEP is 0 at
; the bracket that is the pair of the first one.

SKFN  := @(@(XOB,IPFWD DEPUP ST)=,@(NXOB,SKFN2)=)=
SKFN2 := @(@(XCB,SKFN3)=,@(NXCB,IPFWD ST)=)=
SKFN3 := @(@(XDZ,IPFWD GORUN ST)=,@(NXDZ,IPFWD DEPDN ST)=)=

SKBN  := @(@(XCB,IPBACK DEPUP ST)=,@(NXCB,SKBN2)=)=
SKBN2 := @(@(XOB,SKBN3)=,@(NXOB,IPBACK ST)=)=
SKBN3 := @(@(XDZ,IPFWD GORUN ST)=,@(NXDZ,IPBACK DEPDN ST)=)=

; ------------------------------------------------------------------
; the tests, as a cube with 11 inds
; ------------------------------------------------------------------
XGT  := B11 ANDR XNOR (CH,KGT)=
NXGT := B11 NOT ANDR XNOR (CH,KGT)=
XLT  := B11 ANDR XNOR (CH,KLT)=
NXLT := B11 NOT ANDR XNOR (CH,KLT)=
XPL  := B11 ANDR XNOR (CH,KPL)=
NXPL := B11 NOT ANDR XNOR (CH,KPL)=
XMI  := B11 ANDR XNOR (CH,KMI)=
NXMI := B11 NOT ANDR XNOR (CH,KMI)=
XOB  := B11 ANDR XNOR (CH,KOB)=
NXOB := B11 NOT ANDR XNOR (CH,KOB)=
XCB  := B11 ANDR XNOR (CH,KCB)=
NXCB := B11 NOT ANDR XNOR (CH,KCB)=
XCZ  := B11 NOT ORR CELL ST
NXCZ := B11 ORR CELL ST
XDZ  := B11 DZERO ST
NXDZ := B11 NOT DZERO ST

; ------------------------------------------------------------------
; one request
; ------------------------------------------------------------------
; STEP runs the inner loop and then makes the request that the last step
; needs. The mode at IOD is the load mode or the run mode only.

STEP := IOD LOOP MKP

IOD := @(@(YLOAD,RDREQ ST)=,@(NYLOAD,U1)=)=
U1  := @(@(YIPZ,HALT2)=,@(NYIPZ,U2)=)=
U2  := @(@(YDOT,WRREQ)=,@(NYDOT,U3)=)=
U3  := @(@(YCOM,RDREQ2)=,@(NYCOM,HALT2)=)=

YLOAD  := B13 MLOAD ST
NYLOAD := B13 NOT MLOAD ST
YIPZ   := B13 IPZ0 ST
NYIPZ  := B13 NOT IPZ0 ST
YDOT   := B13 EDOT0
NYDOT  := B13 NOT EDOT0
YCOM   := B13 ECOM0
NYCOM  := B13 NOT ECOM0

; A cube of false bits gives (0,x), so the program is complete.
HALT2 := FALSE =

; A read request is (1,(0,state)). A write request is (1,((1,byte),state)).
RDREQ  := (TRUE =,(FALSE,)=)=
RDREQ2 := (TRUE,(FALSE LEFT,IPFWD ST)=)=
WRREQ  := (TRUE,((TRUE LEFT LEFT,P7 CELL ST)=,IPFWD ST)=)=

; ------------------------------------------------------------------
; after a read
; ------------------------------------------------------------------
; The cube is (1,(byte,state)) with 13 inds. In the load mode the byte goes
; into the program. In the run mode the byte goes into the cell, because a
; "," made the request.

STR := RIGHT RIGHT
INB := LEFT LEFT LEFT LEFT LEFT LEFT LEFT LEFT LEFT RIGHT
INEOF := ORR RIGHT LEFT LEFT LEFT LEFT LEFT LEFT LEFT LEFT RIGHT

AFTREAD := @(@(RLOAD,LOADB)=,@(NRLOAD,STEP CSET)=)=
RLOAD   := B13 MLOAD STR
NRLOAD  := B13 NOT MLOAD STR

; The load stops at a new line, at the end of the input, or at byte 128.
ENL    := ANDR XNOR (INB,KNL)=
EFULL  := NOT ORR IPMF STR
DONEL  := B13 ORR ((ENL,INEOF)=,(EFULL,EFULL)=)=
NDONEL := B13 NOT ORR ((ENL,INEOF)=,(EFULL,EFULL)=)=

LOADB := @(@(DONEL,STEP FINL)=,@(NDONEL,STEP STORL)=)=

; The load is complete: the mode becomes run and the pointer goes to byte 0.
FINL := (PROGF STR,(TAPEF STR,((ONEC IPMF STR,TPMF STR)=,(SHL1 ONEC MODEF STR,DEPF STR)=)=)=)=

; One more byte of the program, and the pointer moves on.
STORL := (NEWPROG,(TAPEF STR,((SHL1 IPMF STR,TPMF STR)=,(MODEF STR,DEPF STR)=)=)=)=
NEWPROG := STB ((PROGF STR,PMASK STR)=,P8 INB)=

; The byte of a "," goes into the cell. At the end of the input the byte is
; 0, because only bit 8 is true.
CSET := (PROGF STR,(NEWTAPE,((IPMF STR,TPMF STR)=,(MODEF STR,DEPF STR)=)=)=)=
NEWTAPE := STB ((TAPEF STR,TMASK STR)=,P7 INB)=

; ------------------------------------------------------------------
; after a write, and the start
; ------------------------------------------------------------------
AFTWRITE := STEP RIGHT

; The first state: the program and the tape are empty, both pointers are at
; 0, the mode is load, and the depth is 0.
INIT := (==========FALSE,(=========FALSE,((ONEC =======FALSE,ONEC =======FALSE)=,(ONEC =======FALSE,ONEC =======FALSE)=)=)=)=

MAIN := [AFTREAD Q13,[AFTWRITE Q12,STEP INIT]]
