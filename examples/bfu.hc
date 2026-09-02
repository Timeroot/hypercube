IO
; bfu.hc - a Brainfuck interpreter with memory of no fixed size.
;
;   echo '++++++++[>++++++++<-]>+.' | hypercube examples/prelude.hc \
;        examples/arith.hc examples/mem.hc examples/bfu.hc
;
; bf.hc holds 128 bytes of program and 64 cells, and no more. This file
; starts with 32 bytes of program and 16 cells, and makes the memory two
; times larger every time it is full. Therefore the memory has no limit in
; the language, and this interpreter shows that hypercube is Turing
; complete: it runs any Brainfuck program with the memory that the program
; needs.
;
; --- how the memory becomes larger ---
; The program (,FALSE)= gives a cube of one ind more. The old bits stay in
; the low half, so every position keeps its number. GROW does this to every
; part of the state at the same time.
;
; --- the two rules that a program of no fixed size must follow ---
; 1. No fixed number of = operations. A program cannot make a bit into a
;    cube of 11 inds, because the state may have 12 inds tomorrow. Every
;    test must therefore be a program that keeps the shape of the state:
;        ANY AND (,MASK)=
;    ANY gives the answer at every position of the state, whatever the size
;    of the state is. MASK is a state with true bits at one field only, and
;    a mask is easy to build with the same rebuild that changes a field.
; 2. No test with @ around a step that changes the size. The two halves of
;    a split must have the same inds, so @(C,A)= needs A and C of one size.
;    A block does not compare the two parts, so
;        [ A KEEP , B ]
;    is a choice between A and B where A and B may give different sizes.
;    KEEP gives the cube again if a test is true, and fails if it is false:
;        AND (,@(TEST,FAILB)=)=
;    The lazy rule of @ skips FAILB when TEST is false everywhere.

; ------------------------------------------------------------------
; the parts of the state
; ------------------------------------------------------------------
; state = ( PROG , ( TAPE , ( ( IPM , TPM ) , ( MODE , DEP ) ) ) )
; A state with s inds holds 2^(s-4) bytes of program and 2^(s-5) cells.
; IPM has one bit for each byte of the program. The low half of TPM has one
; bit for each cell, so TPM has room for the step that goes over the end.

PROGF := LEFT
TAPEF := LEFT RIGHT
IPMF  := LEFT LEFT RIGHT RIGHT
TPMF  := RIGHT LEFT RIGHT RIGHT
MODEF := LEFT RIGHT RIGHT RIGHT
DEPF  := RIGHT RIGHT RIGHT RIGHT

; ------------------------------------------------------------------
; masks: a state with true bits at one field only
; ------------------------------------------------------------------
MIPM  := (FALSE PROGF,(FALSE TAPEF,((TRUE IPMF,FALSE TPMF)=,(FALSE MODEF,FALSE DEPF)=)=)=)=
MITOP := (FALSE PROGF,(FALSE TAPEF,((TOPC IPMF,FALSE TPMF)=,(FALSE MODEF,FALSE DEPF)=)=)=)=
MTPM  := (FALSE PROGF,(FALSE TAPEF,((FALSE IPMF,TRUE TPMF)=,(FALSE MODEF,FALSE DEPF)=)=)=)=
MTPL  := (FALSE PROGF,(FALSE TAPEF,((FALSE IPMF,(TRUE LEFT,FALSE LEFT)= TPMF)=,(FALSE MODEF,FALSE DEPF)=)=)=)=
MM0   := (FALSE PROGF,(FALSE TAPEF,((FALSE IPMF,FALSE TPMF)=,(ONEC MODEF,FALSE DEPF)=)=)=)=
MM1   := (FALSE PROGF,(FALSE TAPEF,((FALSE IPMF,FALSE TPMF)=,(SHL1 ONEC MODEF,FALSE DEPF)=)=)=)=
MM2   := (FALSE PROGF,(FALSE TAPEF,((FALSE IPMF,FALSE TPMF)=,(SHL1 SHL1 ONEC MODEF,FALSE DEPF)=)=)=)=
MM3   := (FALSE PROGF,(FALSE TAPEF,((FALSE IPMF,FALSE TPMF)=,(SHL1 SHL1 SHL1 ONEC MODEF,FALSE DEPF)=)=)=)=
MM4   := (FALSE PROGF,(FALSE TAPEF,((FALSE IPMF,FALSE TPMF)=,(SHL1 SHL1 SHL1 SHL1 ONEC MODEF,FALSE DEPF)=)=)=)=
MD0   := (FALSE PROGF,(FALSE TAPEF,((FALSE IPMF,FALSE TPMF)=,(FALSE MODEF,ONEC DEPF)=)=)=)=

; ------------------------------------------------------------------
; tests: the answer at every position of the state
; ------------------------------------------------------------------
ISLOAD := ANY AND (,MM0)=
ISRUN  := ANY AND (,MM1)=
ISSKF  := ANY AND (,MM2)=
ISSKB  := ANY AND (,MM3)=
ISWAIT := ANY AND (,MM4)=
DEPZ   := ANY AND (,MD0)=
IPZ    := NOT ANY AND (,MIPM)=      ; the program pointer is off the end
IPTOP  := ANY AND (,MITOP)=         ; the program pointer is at the last byte
TPZ    := NOT ANY AND (,MTPM)=      ; the tape pointer went below cell 0
TPOUT  := NOT ANY AND (,MTPL)=      ; the tape pointer went over the last cell
NEEDG  := AND (TPOUT,NOT TPZ)=      ; a larger tape is necessary

; ------------------------------------------------------------------
; the byte at each pointer, at every byte of the state
; ------------------------------------------------------------------
PMASK := STR3 IPMF
TMASK := STR3 LEFT TPMF
ICUBE := = BSEL (PROGF,PMASK)=
CCUBE := == BSEL (TAPEF,TMASK)=

; ------------------------------------------------------------------
; the characters of Brainfuck, at every byte of a cube of any size
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

RGT  := [=#LEFT Q4B,KGT]
RLT  := [=#LEFT Q4B,KLT]
RPL  := [=#LEFT Q4B,KPL]
RMI  := [=#LEFT Q4B,KMI]
RDOT := [=#LEFT Q4B,KDOT]
RCOM := [=#LEFT Q4B,KCOM]
ROB  := [=#LEFT Q4B,KOB]
RCB  := [=#LEFT Q4B,KCB]
RNL  := [=#LEFT Q4B,KNL]

; ------------------------------------------------------------------
; new states
; ------------------------------------------------------------------
IPFWD  := (PROGF,(TAPEF,((SHL1 IPMF,TPMF)=,(MODEF,DEPF)=)=)=)=
IPBACK := (PROGF,(TAPEF,((SHR1 IPMF,TPMF)=,(MODEF,DEPF)=)=)=)=
TPFWD  := (PROGF,(TAPEF,((IPMF,SHL1 TPMF)=,(MODEF,DEPF)=)=)=)=
TPBACK := (PROGF,(TAPEF,((IPMF,SHR1 TPMF)=,(MODEF,DEPF)=)=)=)=
DEPUP  := (PROGF,(TAPEF,((IPMF,TPMF)=,(MODEF,SHL1 DEPF)=)=)=)=
DEPDN  := (PROGF,(TAPEF,((IPMF,TPMF)=,(MODEF,SHR1 DEPF)=)=)=)=
GORUN  := (PROGF,(TAPEF,((IPMF,TPMF)=,(SHL1 ONEC MODEF,DEPF)=)=)=)=
GOSKF  := (PROGF,(TAPEF,((IPMF,TPMF)=,(SHL1 SHL1 ONEC MODEF,ONEC DEPF)=)=)=)=
GOSKB  := (PROGF,(TAPEF,((IPMF,TPMF)=,(SHL1 SHL1 SHL1 ONEC MODEF,ONEC DEPF)=)=)=)=
GOWAIT := (PROGF,(TAPEF,((SHL1 IPMF,TPMF)=,(SHL1 SHL1 SHL1 SHL1 ONEC MODEF,DEPF)=)=)=)=
FINL   := (PROGF,(TAPEF,((ONEC IPMF,TPMF)=,(SHL1 ONEC MODEF,DEPF)=)=)=)=
CELLUP := (PROGF,(TINC,((IPMF,TPMF)=,(MODEF,DEPF)=)=)=)=
CELLDN := (PROGF,(TDEC,((IPMF,TPMF)=,(MODEF,DEPF)=)=)=)=

; The new byte comes from BSEL, so no fixed number of = is necessary.
TINC := STB ((TAPEF,TMASK)=,= REPB INC0 BSEL (TAPEF,TMASK)=)=
TDEC := STB ((TAPEF,TMASK)=,= REPB DEC0 BSEL (TAPEF,TMASK)=)=

; GROW makes every part of the state two times larger. GROWL does the same
; and puts the program pointer at the first byte of the new half.
GROW  := ((PROGF,FALSE PROGF)=,((TAPEF,FALSE TAPEF)=,(((IPMF,FALSE IPMF)=,(TPMF,FALSE TPMF)=)=,((MODEF,FALSE MODEF)=,(DEPF,FALSE DEPF)=)=)=)=)=
GROWL := ((PROGF,FALSE PROGF)=,((TAPEF,FALSE TAPEF)=,(((FALSE IPMF,ONEC IPMF)=,(TPMF,FALSE TPMF)=)=,((MODEF,FALSE MODEF)=,(DEPF,FALSE DEPF)=)=)=)=)=

; ------------------------------------------------------------------
; the pair (byte of the program, state)
; ------------------------------------------------------------------
MKP := (ICUBE,)=
CHP := LEFT
ST  := RIGHT

EGT  := NOT ANY XOR (CHP,RGT CHP)=
NEGT := ANY XOR (CHP,RGT CHP)=
ELT  := NOT ANY XOR (CHP,RLT CHP)=
NELT := ANY XOR (CHP,RLT CHP)=
EPL  := NOT ANY XOR (CHP,RPL CHP)=
NEPL := ANY XOR (CHP,RPL CHP)=
EMI  := NOT ANY XOR (CHP,RMI CHP)=
NEMI := ANY XOR (CHP,RMI CHP)=
EDOT := NOT ANY XOR (CHP,RDOT CHP)=
ECOM := NOT ANY XOR (CHP,RCOM CHP)=
EOB  := NOT ANY XOR (CHP,ROB CHP)=
NEOB := ANY XOR (CHP,ROB CHP)=
ECB  := NOT ANY XOR (CHP,RCB CHP)=
NECB := ANY XOR (CHP,RCB CHP)=
EZ   := NOT ANY CHP

; ------------------------------------------------------------------
; one Brainfuck step
; ------------------------------------------------------------------
; NEXT never changes the size of the state, so a test with @ is correct
; here. The tape pointer may go over the last cell, and LOOP then stops.

NEXT := @(@(ISSKF ST,SKFN)=,@(NOT ISSKF ST,NX2)=)=
NX2  := @(@(ISSKB ST,SKBN)=,@(NOT ISSKB ST,RUNN)=)=

RUNN := @(@(EGT,TPFWD IPFWD ST)=,@(NEGT,V2)=)=
V2   := @(@(ELT,TPBACK IPFWD ST)=,@(NELT,V3)=)=
V3   := @(@(EPL,IPFWD CELLUP ST)=,@(NEPL,V4)=)=
V4   := @(@(EMI,IPFWD CELLDN ST)=,@(NEMI,V5)=)=
V5   := @(@(EOB,OPENB)=,@(NEOB,V6)=)=
V6   := @(@(ECB,CLOSEB)=,@(NECB,IPFWD ST)=)=

OPENB  := @(@(CZ,IPFWD GOSKF ST)=,@(NCZ,IPFWD ST)=)=
CLOSEB := @(@(NCZ,IPBACK GOSKB ST)=,@(CZ,IPFWD ST)=)=
CZ  := NOT ANY CCUBE ST
NCZ := ANY CCUBE ST

SKFN  := @(@(EOB,IPFWD DEPUP ST)=,@(NEOB,SKFN2)=)=
SKFN2 := @(@(ECB,SKFN3)=,@(NECB,IPFWD ST)=)=
SKFN3 := @(@(DEPZ ST,IPFWD GORUN ST)=,@(NOT DEPZ ST,IPFWD DEPDN ST)=)=

SKBN  := @(@(ECB,IPBACK DEPUP ST)=,@(NECB,SKBN2)=)=
SKBN2 := @(@(EOB,SKBN3)=,@(NEOB,IPBACK ST)=)=
SKBN3 := @(@(DEPZ ST,IPFWD GORUN ST)=,@(NOT DEPZ ST,IPBACK DEPDN ST)=)=

; ------------------------------------------------------------------
; the inner loop
; ------------------------------------------------------------------
; A block makes the loop, not a test with @, because the state may become
; larger. KEEPC gives the pair again while the loop must go on.

LOOP  := [# MKP NEXT KEEPC,]
KEEPC := AND (,@(= STOPC,FAILB)=)=

STOPC := OR (SC2,RUNIO)=
SC2   := OR (SC1,TPOUT ST)=
SC1   := OR (ISLOAD ST,IPZ ST)=
RUNIO := AND (ISRUN ST,IOCH)=
IOCH  := OR (OR (EDOT,ECOM)=,EZ)=

; ------------------------------------------------------------------
; one request
; ------------------------------------------------------------------
; CYC makes the tape larger and runs the loop again, or gives the request
; of the last step. Both parts of a block may give a different size.

STEP := CYC LOOP MKP
CYC  := [# LOOP MKP GROW ST KEEPG,IOD]
KEEPG := AND (,@(= NOT NEEDG ST,FAILB)=)=

IOD  := [RDREQ ST GLOAD,IOD2]
IOD2 := [HALTP GEND,IOD3]
IOD3 := [WRREQ GDOT,IOD4]
IOD4 := [RDREQ2 GCOM,HALTP]

GLOAD := AND (,@(= NOT ISLOAD ST,FAILB)=)=
GEND  := AND (,@(= NOT OR (IPZ ST,TPZ ST)=,FAILB)=)=
GDOT  := AND (,@(= NOT EDOT,FAILB)=)=
GCOM  := AND (,@(= NOT ECOM,FAILB)=)=

HALTP := FALSE

; A read request is (1,(0,state)). A write request is
; (1,((1,byte),(0,state))). Both give back a cube of the same shape:
; (1,(byte,state)). The mode says which request the program made.
RDREQ  := (TRUE =,(FALSE,)=)=
RDREQ2 := (TRUE,(FALSE LEFT,GOWAIT ST)=)=
WRREQ  := (TRUE =,((TRUE LEFT,CCUBE ST)=,(FALSE LEFT,IPFWD ST)=)=)=

; ------------------------------------------------------------------
; after a read or a write
; ------------------------------------------------------------------
; The cube is (1,(byte,state)). After a write the byte part is false.

STV := LEFT RIGHT
STS := RIGHT RIGHT

AFTER  := [LOADB GLOADR,AFTER2]
AFTER2 := [STEP CSET GWAITR,STEP STS]
GLOADR := AND (,@(== NOT ISLOAD STS,FAILB)=)=
GWAITR := AND (,@(== NOT ISWAIT STS,FAILB)=)=

; the byte of a "," goes into the cell, and the mode becomes run
CSET := (PROGF STS,(NEWTAPE,((IPMF STS,TPMF STS)=,(SHL1 ONEC MODEF STS,DEPF STS)=)=)=)=
NEWTAPE := STB ((TAPEF STS,TMASK STS)=,LEFT REPB STV)=

; The load stops at a new line or at the end of the input. If the program
; store is full, GROWL makes it two times larger.
LOADB  := [STEP FINL STS GDONE,LOADB2]
LOADB2 := [STEP GROWL STORB GFULL,STEP IPFWD STORB]
GDONE  := AND (,@(== NOT OR (ENL,INEOF)=,FAILB)=)=
GFULL  := AND (,@(== NOT IPTOP STS,FAILB)=)=

ENL   := NOT ANY XOR (REPB STV,RNL STV)=
; M8 is a mask of the shape of the byte cube, with bits 8 to 15 true.
; The end of the input sets bit 8, so this test needs no fixed shape.
M8    := [(#,FALSE)Q5B,(FALSE LEFT,TRUE LEFT)=]
Q5B   := (((((,),),),),)
INEOF := ANY AND (STV,M8 STV)=

STORB := (NEWPROG,(TAPEF STS,((IPMF STS,TPMF STS)=,(MODEF STS,DEPF STS)=)=)=)=
NEWPROG := STB ((PROGF STS,PMASK STS)=,REPB STV)=

; ------------------------------------------------------------------
; the start
; ------------------------------------------------------------------
; The first state has 9 inds: 32 bytes of program and 16 cells. The
; interpreter makes it larger when it needs more.
INIT := (========FALSE,(=======FALSE,((ONEC =====FALSE,ONEC =====FALSE)=,(ONEC =====FALSE,ONEC =====FALSE)=)=)=)=

Q11 := (((((((((((,),),),),),),),),),),)

MAIN := [AFTER Q11,STEP INIT]
