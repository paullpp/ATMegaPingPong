;***********************************************************
;*
;*	This is Lab 7 of ECE 375 at Oregon State University
;*
;*  Rock Paper Scissors
;* 	Requirement:
;* 	1. USART1 communication
;* 	2. Timer/counter1 Normal mode to create a 1.5-sec delay
;***********************************************************
;*
;*	 Authors: Paul Lipp and Ryan Muriset
;*	 Date: 2023-03-11
;*
;***********************************************************

.include "m32U4def.inc"         ; Include definition file

;***********************************************************
;*  Internal Register Definitions and Constants
;***********************************************************
.def    mpr = r16               ; Multi-Purpose Register
.def	counter = r19
.def	play = r23
.def	opplay = r18

; Use this signal code between two boards for their game ready
.equ    ReadyComp = $FF
.equ	PD_seven = 7
.equ	PD_four = 4
.def	waitcnt = r17				; Wait Loop Counter
.def	ilcnt = r25				; Inner Loop Counter
.def	olcnt = r24				; Outer Loop Counter

.equ	WTime = 15

;***********************************************************
;*  Start of Code Segment
;***********************************************************
.cseg                           ; Beginning of code segment

;***********************************************************
;*  Interrupt Vectors
;***********************************************************
.org    $0000                   ; Beginning of IVs
	    rjmp    INIT            	; Reset interrupt

.org	$0002
		rcall HandleINT0
		reti

.org	$0032
		rcall HandleRECX
		reti

.org    $0056                   ; End of Interrupt Vectors

;***********************************************************
;*  Program Initialization
;***********************************************************
INIT:
	;Stack Pointer (VERY IMPORTANT!!!!)

	; Initialize the Stack Pointer

		ldi	mpr, low(RAMEND)	; Initialize Stack Pointer
		out SPL, mpr
		ldi mpr, high(RAMEND)
		out SPH, mpr

	;I/O Ports
		ldi mpr, $00			; Initialize Port D for input
		out DDRD, mpr
		ldi mpr, $FF
		out PORTD, mpr

		ldi mpr, $FF
		out DDRB, mpr
		ldi mpr, $00
		out PORTB, mpr

	;USART1
		;Set baudrate at 2400bps
		;Enable receiver and transmitter
		;Set frame format: 8 data bits, 2 stop bits
		;Set baudrate at 2400bps
		ldi mpr, $00
		sts	UBRR1H, mpr
		ldi mpr, $CF
		sts UBRR1L, mpr

		ldi mpr, (1<<UDRE1)
		sts UCSR1A, mpr

		;Enable receiver and transmitter
		ldi mpr, (1<<RXCIE1)|(1<<RXEN1)|(1<<TXEN1)
		sts	UCSR1B, mpr

		;Set frame format: 8 data bits, 2 stop bits
		ldi mpr, (1<<USBS1)|(3<<UCSZ10)
		sts UCSR1C, mpr

	;TIMER/COUNTER1
		;Set Normal mode, 256 pre-scaler
		
		ldi mpr, 0b00000000
		sts TCCR1A, mpr

		ldi mpr, 0b00000100
		sts TCCR1B, mpr

		ldi		mpr, $02
		sts		EICRA, mpr
		

	;Other
	;Initialize LCD

		rcall LCDInit
		rcall LCDClr
		
		ldi ZL, low(Init_START<<1)
		ldi ZH, high(Init_START<<1)
		ldi YL, $00
		ldi YH, $01
		ldi counter, 8

		rcall InitWriteL1

		ldi ZL, low(InitL2_START<<1)
		ldi ZH, high(InitL2_START<<1)
		ldi YL, $10
		ldi YH, $01
		ldi counter, 16

		rcall InitWriteL2

	;Write initial welcome to LCD

		ldi play, $00

		ldi mpr, $01
		out EIMSK, mpr

		ldi opplay, $00

		;sei
	;Initialize the LCD
		


;***********************************************************
;*  Main Program
;***********************************************************
MAIN:
		in mpr, PIND			;Polling PIND
		andi mpr, (1<<7)		;Check for PD7 press
		cpi mpr, (1<<7)
		breq NEXT
		rcall WAITING			;Start Game Routines
		ret

NEXT:
		rjmp MAIN

;***********************************************************
;*	Functions and Subroutines
;***********************************************************



WAITING:
		ldi ZL, low(PressedL1_START<<1)
		ldi ZH, high(PressedL1_START<<1)
		ldi YL, $00
		ldi YH, $01
		ldi counter, 14

		rcall ReadyWrLn1

		ldi ZL, low(PressedL2_START<<1)
		ldi ZH, high(PressedL2_START<<1)
		ldi YL, $10
		ldi YH, $01
		ldi counter, 16

		rcall ReadyWrLn2
		;Write Ready Lines 1 and 2

		rcall SendReady		;Send Ready USART1
		rcall LCDClr		
		rcall Game			;Call Game Routine
		sei
		rcall SendResult	;SendResult to USART1
		ldi waitcnt, 50		;Wait to allow interrupt to trigger
		rcall Wait		
		cli
		rcall EvalGame		;Write both plays to LCD
		rcall LCDClr
		rcall WritePlay1	
		rcall PrintResult	;Write Result
		
		;LEDs Countdown Script
		ldi mpr, (1<<7|1<<6|1<<5|1<<4)
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|1<<6|1<<5|1<<4)
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|0<<6|1<<5|1<<4)
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|0<<6|0<<5|1<<4)
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|0<<6|0<<5|0<<4)
		out PORTB, mpr

		ret

;***********************************************************
;*	Called when PD7 is pressed. Writes Waiting for player
;*  and calls SendReady. Starts Game once SendReady returns
;***********************************************************

SendReady:
		ldi mpr, $FF		;Send Ready ($FF) to USART1
		sts UDR1, mpr

		lds mpr, UDR1		;Poll for Ready from USART1
		cpi mpr, $FF
		brne SendReady
		ret

;***********************************************************
;*	Sends FF to USART UDR1, then polls UDR1 to wait for Ready
;*  from other board. Returns to Waiting
;***********************************************************

HandleINT0:
		cli
		inc play			;Service INT0, Cycle Play Options on LCD
		cpi play, $03
		breq Handle2
		rcall WritePlay1
		sbi EIFR, 0
		ldi waitcnt, WTime
		rcall Wait
		sei
		ret
Handle2:
		rcall Reset
		ret

;***********************************************************
;*	Interrupt Service, Increments play reg
;***********************************************************


Game:
		sei							;Interrupts are enabled during this routine to 
									;allow for cycling of line 2 options
		rcall WriteLine1Start		;Write "game start" prompt Line 1
		rcall WritePlay1			;Write option Line 2
		ldi mpr, (1<<7|1<<6|1<<5|1<<4)		;LED Countdown Script
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|1<<6|1<<5|1<<4)
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|0<<6|1<<5|1<<4)
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|0<<6|0<<5|1<<4)
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|0<<6|0<<5|0<<4)
		out PORTB, mpr
		ldi mpr, $00
		out EIMSK, mpr

		cli
		ret

;***********************************************************
;*  TimerCounter1 Loop
;*  Has TC1 Count to 18660, which is 65535 - 46875
;*	8/256 = 0.03125 = 32000ns, 32000*x = 1.5s
;*  1.5s/32000 = x; x = 46875
;***********************************************************

TimerLoop:
		ldi mpr, $48				
		sts TCNT1H, mpr
		ldi mpr, $E5
		sts TCNT1L, mpr
TimerLoopHelper:
		sbis TIFR1, 0
		rjmp TimerLoopHelper
		sbi TIFR1, 0
		ret

Reset:
		ldi play, $00
		rcall LCDClrLn2
		rcall WritePlay1
		ret

;***********************************************************
;*	Main Game Routine
;***********************************************************

SendResult:
		lds mpr, UCSR1A
		sbrs mpr, UDRE1
		rjmp SendResult
		sts UDR1, play
		ret

HandleRECX:							;USART1 RXC1 Interrupt Service Routine. Retrieves Data from UDR1
		lds mpr, UCSR1A
		sbrs mpr, RXC1
		rjmp HandleRECX
		lds opplay, UDR1

		ret


;***********************************************************
;*	Send Result to other board
;***********************************************************

EvalGame:
		rcall LCDClr
		rcall WriteOpPlay1		;opplay - Write Opponents Play to Line2
		rcall WritePlay1Ln1		;play   - Write Play to line1
		
		ldi mpr, (1<<7|1<<6|1<<5|1<<4)	; LED Countdown Script
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|1<<6|1<<5|1<<4)
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|0<<6|1<<5|1<<4)
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|0<<6|0<<5|1<<4)
		out PORTB, mpr
		rcall TimerLoop
		ldi mpr, (0<<7|0<<6|0<<5|0<<4)
		out PORTB, mpr
		ret

;***********************************************************
;*	Print both hands
;***********************************************************

PrintResult:								; Print Winner of Game
		cp play, opplay
		brne Print2
		rcall WriteResultDraw
		ret
Print2:
		cpi play, $00						; 00 01 02		00 beats 02 || 01 beats 00 || 02 beats 01
		brne Print3
		rcall PrintResultHelper1
		ret
Print3:
		cpi play, $01
		brne Print4
		rcall PrintResultHelper2
		ret
Print4:
		cpi opplay, $01
		breq PrintWin
		rcall WriteResultLoss
		ret
PrintWin:
		rcall WriteResultWin
		ret

PrintResultHelper1:
		cpi opplay, $02
		brne PrintLossHelper1
		rcall WriteResultWin
		ret
PrintLossHelper1:
		rcall WriteResultLoss
		ret

PrintResultHelper2:
		cpi opplay, $00
		brne PrintLossHelper2
		rcall WriteResultWin
		ret
PrintLossHelper2:
		rcall WriteResultLoss
		ret

;***********************************************************
;*	Print Result
;***********************************************************

;**********************************************************************************************************************
;**********************************************************************************************************************


;***********************************************************
;*	Write Functions
;***********************************************************

WriteLine1Start:
		ldi ZL, low(Start_START<<1)
		ldi ZH, high(Start_START<<1)
		ldi YL, $00
		ldi YH, $01
		ldi counter, 10

		rcall WriteLine1Helper
		ret

WriteLine1Helper:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne WriteLine1Helper

		rcall LCDWrLn1
		ret

;****************************************************

WritePlay1:
		cpi play, $00
		brne WritePlay2
		ldi ZL, low(Rock_START<<1)
		ldi ZH, high(Rock_START<<1)
		ldi YL, $10
		ldi YH, $01
		ldi counter, 4

		rcall WriteRock
		ret
WritePlay2:
		cpi play, $01
		brne WritePlay3
		ldi ZL, low(Paper_START<<1)
		ldi ZH, high(Paper_START<<1)
		ldi YL, $10
		ldi YH, $01
		ldi counter, 5

		rcall WritePaper
		ret
WritePlay3:
		ldi ZL, low(Scissor_START<<1)
		ldi ZH, high(Scissor_START<<1)
		ldi YL, $10
		ldi YH, $01
		ldi counter, 8
		rcall WriteScissors
		ret

WritePlay4:
		ret

;*********************************************************

WriteOpPlay1:
		cpi opplay, $00
		brne WriteOpPlay2
		ldi ZL, low(Rock_START<<1)
		ldi ZH, high(Rock_START<<1)
		ldi YL, $10
		ldi YH, $01
		ldi counter, 4

		rcall WriteRock
		ret
WriteOpPlay2:
		cpi opplay, $01
		brne WriteOpPlay3
		ldi ZL, low(Paper_START<<1)
		ldi ZH, high(Paper_START<<1)
		ldi YL, $10
		ldi YH, $01
		ldi counter, 5

		rcall WritePaper
		ret
WriteOpPlay3:
		cpi opplay, $02
		brne WriteOpPlay4
		ldi ZL, low(Scissor_START<<1)
		ldi ZH, high(Scissor_START<<1)
		ldi YL, $10
		ldi YH, $01
		ldi counter, 8
		rcall WriteScissors
		ret

WriteOpPlay4:
		ldi YL, $10			
		ldi YH, $01

		ldi mpr, $30
		add opplay, mpr
		st Y+, opplay		

		rcall LCDWrLn2
		ret

;*********************************************************

WritePlay1Ln1:
		cpi play, $00
		brne WritePlay2Ln1
		ldi ZL, low(Rock_START<<1)
		ldi ZH, high(Rock_START<<1)
		ldi YL, $00
		ldi YH, $01
		ldi counter, 4

		rcall WriteRockLn1
		ret
WritePlay2Ln1:
		cpi play, $01
		brne WritePlay3Ln1
		ldi ZL, low(Paper_START<<1)
		ldi ZH, high(Paper_START<<1)
		ldi YL, $00
		ldi YH, $01
		ldi counter, 5

		rcall WritePaperLn1
		ret
WritePlay3Ln1:
		ldi ZL, low(Scissor_START<<1)
		ldi ZH, high(Scissor_START<<1)
		ldi YL, $00
		ldi YH, $01
		ldi counter, 8
		rcall WriteScissorsLn1
		ret

WritePlay4Ln1:
		ret

;**************************************************************

WriteRock:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne WriteRock

		rcall LCDWrLn2
		ret

WritePaper:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne WritePaper

		rcall LCDWrLn2
		ret

WriteScissors:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne WriteScissors

		rcall LCDWrLn2
		ret

;*************************************************************

WriteRockLn1:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne WriteRockLn1

		rcall LCDWrLn1
		ret

WritePaperLn1:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne WritePaperLn1

		rcall LCDWrLn1
		ret

WriteScissorsLn1:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne WriteScissorsLn1

		rcall LCDWrLn1
		ret

;***********************************************************
;*	Writes Play (RPS)
;***********************************************************

InitWriteL1:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne InitWriteL1

		rcall LCDWrLn1
		ret

InitWriteL2:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne InitWriteL2

		rcall LCDWrLn2
		ret

;***********************************************************
;*	Write Initial Message (Welcome!)
;***********************************************************

ReadyWrLn1:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne ReadyWrLn1

		rcall LCDWrLn1
		ret

ReadyWrLn2:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne ReadyWrLn2

		rcall LCDWrLn2
		ret

;***********************************************************
;*  Write Functions to write Ready, waiting for other player
;***********************************************************

WriteResultWin:
		ldi ZL, low(WIN_START<<1)
		ldi ZH, high(WIN_START<<1)
		ldi YL, $00
		ldi YH, $01
		ldi counter, 4

WriteWin2:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne WriteWin2

		rcall LCDWrLn1
		ret

WriteResultLoss:
		ldi ZL, low(LOSS_START<<1)
		ldi ZH, high(LOSS_START<<1)
		ldi YL, $00
		ldi YH, $01
		ldi counter, 5

WriteLoss2:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne WriteLoss2

		rcall LCDWrLn1
		ret

WriteResultDraw:
		ldi ZL, low(DRAW_START<<1)
		ldi ZH, high(DRAW_START<<1)
		ldi YL, $00
		ldi YH, $01
		ldi counter, 5

WriteDraw2:
		lpm mpr, Z+
		st Y+, mpr
		dec counter
		brne WriteDraw2

		rcall LCDWrLn1
		ret
;***********************************************************
;*  Write Functions to write Result
;***********************************************************


Wait:
		push	waitcnt			; Save wait register
		push	ilcnt			; Save ilcnt register
		push	olcnt			; Save olcnt register

Loop:	ldi		olcnt, 224		; load olcnt register
OLoop:	ldi		ilcnt, 237		; load ilcnt register
ILoop:	dec		ilcnt			; decrement ilcnt
		brne	ILoop			; Continue Inner Loop
		dec		olcnt		; decrement olcnt
		brne	OLoop			; Continue Outer Loop
		dec		waitcnt		; Decrement wait
		brne	Loop			; Continue Wait loop

		pop		olcnt		; Restore olcnt register
		pop		ilcnt		; Restore ilcnt register
		pop		waitcnt		; Restore wait register
		ret				; Return from subroutine

;***********************************************************
;*	Stored Program Data
;***********************************************************

;-----------------------------------------------------------
; An example of storing a string. Note the labels before and
; after the .DB directive; these can help to access the data
;-----------------------------------------------------------

Init_START:
	.DB		"Welcome!"
Init_END:

InitL2_START:
	.DB		"Please Press PD7"
InitL2_END:

PressedL1_START:
	.DB		"Ready. Waiting"
PressedL1_END:

PressedL2_START:
	.DB		"for the opponent"
PressedL2_END:

Start_START:
	.DB		"Game Start"
Start_END:

Rock_START:
    .DB		"Rock"		; Declaring data in ProgMem
Rock_END:

Paper_START:
    .DB		"Paper"		; Declaring data in ProgMem
Paper_END:

Scissor_START:
    .DB		"Scissors"		; Declaring data in ProgMem
Scissor_END:

WIN_START:
    .DB		"WIN!"		; Declaring data in ProgMem
WIN_END:

LOSS_START:
    .DB		"LOSS!"		; Declaring data in ProgMem
LOSS_END:

DRAW_START:
    .DB		"DRAW!"		; Declaring data in ProgMem
DRAW_END:

;***********************************************************
;*	Additional Program Includes
;***********************************************************
.include "LCDDriver.asm"		; Include the LCD Driver
