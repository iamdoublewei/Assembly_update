;-------------------------------------------------------------------------------
; main.asm
; Author: Wei Wei
; Vesion: 1.0
; Last Edited: 8/24/2022
; Email: iamdoublewei@gmail.com

;--------------------------------------------------------------------------------
; MSP430 jump instruction encoding calculation
; 001   ,         111    ,      0100010011
; opcode, unconditional jump, 10 bits 2's complement representation offset
; formula: PC(new) = PC(old) + 2 + PC(offset) * 2
; in this complementation we use 001,111,0000000000(0x3C00) + calculation offset
;
; MSP430 jump instruction calculation
; jmp 0
; jmp to the absolute address related to start address
; start address of the program: 0x4000 (can be set through .cmd file)
; to calculate the jmp instruction, use current address - start address

;-------------------------------------------------------------------------------
; Research Notes:
; 1. To serve the research purpose and avoid some function call instructions or jump
; 	 instructions. This project intentionally make some duplicated code which may looks
;	 unnecessary and messy.
; Current Thinking:
; 1. How to define update and decode, should we seperate into two functions or combine
; 2. Unavoidable to replace a jump instruction. Maybe also need to remove backup size from encoding
; 3. Seperate modify into replacement and insert

;-------------------------------------------------------------------------------
            	.cdecls C,LIST,"msp430.h"       ; Include device header file
            
;-------------------------------------------------------------------------------
            	.def    RESET                   ; Export program entry-point to
                                            ; make it known to linker.
;-------------------------------------------------------------------------------
            	.text                           ; Assemble into program memory.
            	.retain                         ; Override ELF conditional linking
                                            ; and retain current section.
            	.retainrefs                     ; And retain any sections that have
                                            ; references to current section.

;-------------------------------------------------------------------------------
RESET       	mov.w   #__STACK_END,SP         ; Initialize stackpointer
StopWDT     	mov.w   #WDTPW|WDTHOLD,&WDTCTL  ; Stop watchdog timer


;-------------------------------------------------------------------------------
; Main start from here
;-------------------------------------------------------------------------------

_main

MPY32_MPY 		.equ 	0x04C0
MPY32_OP2		.equ 	0x04C8
MPY32_RESLO		.equ 	0x04CA
MPY32_MPY32L	.equ    0x04D0
MPY32_MPY32H	.equ    0x04D2
MPY32_OP2L		.equ	0x04E0
MPY32_OP2H		.equ	0x04E2
MPY32_RES0		.equ	0x04E4
MPY32_RES1		.equ	0x04E6

;-------------------------------------------------------------------------------
; Variable Definitions
; 1. free_address: the starting address of free memory space
; 2. update_avail: 1: update packet available in rx_buffer
; 3. sizerx: the size of update packet stored in rx_buffer in bytes
; 4. rx_buffer: stored received update packet
;    byte 0: opcode
;	 byte 1: destination address lower 8 bits
;	 byte 2: destination address higher 8 bits
;	 byte 3: length of the following update data in words(16 bits)
; 	 byte 4: update data 0 lower 8 bits
;	 byte 5: update data 0 higher 8 bits
;	 ...

_init
				.text
				.global free_address,update_avail,rx_buffer,sizerx,init,check_update
SetupP1     	bic.b   #BIT0,&P1OUT            ; Clear P1.0 output latch for a defined power-on state
            	bis.b   #BIT0,&P1DIR            ; Set P1.0 to output direction
SetupP2     	bic.b   #BIT1,&P1OUT            ; Clear P1.1 output latch for a defined power-on state
            	bis.b   #BIT1,&P1DIR            ; Set P1.1 to output direction
UnlockGPIO  	bic.w   #LOCKLPM5,&PM5CTL0      ; Disable the GPIO power-on default
                                            ; high-impedance mode to activate
                                            ; previously configured port settings
				call 	#init

_loop
;-------------------------------------------------------------------------------
; Benchmarks
; 1. 8 bit math: multiplication, division, subtraction and addition
; 2. 16 bit math: multiplication, division, subtraction and addition
; 3. 32 bit math: multiplication, division, subtraction and addition

math8bit		mov.b	#0x0002,R13				; Multiplication
				mov.b	#0x0004,R12
				mov.w   R13,&MPY32_MPY			; Load operand 1 into multiplier
				mov.w   R12,&MPY32_OP2			; Load operand 2 which triggers MPY
				mov.w   &MPY32_RESLO,R12		; Move result into return register
				mov.b	#0x0003,R13				; Addition
				mov.b	#0x000c,R12
				add.b   R13,R12

;math16bit		mov.w	#0x00e7,R13
;				mov.w	#0x000c,R12
;				add.w   R13,R12
;				mov.w	#0x0002,R13
;				mov.w	#0x0004,R12
;				mov.w   R13,&MPY32_MPY			; Load operand 1 into multiplier
;				mov.w   R12,&MPY32_OP2			; Load operand 2 which triggers MPY
;				mov.w   &MPY32_RESLO,R12		; Move result into return register
;				mov.w   #0x0012,R13
;				mov.w   #0x003,R14
;				call 	#div

math32bit		mov.w   #0x0075,R14
				mov.w   #0x00a8,R15
				mov.w   #0x00e7,R12
				mov.w   #0x0038,R13
				add.w   R14,R12
				addc.w  R15,R13 				; Addition
				mov.w   #0x0075,R14
				mov.w   #0x00a8,R15
				mov.w   #0x00e7,R12
				mov.w   #0x0038,R13
				mov.w   R12,&MPY32_MPY32L		; Load operand 1 Low into multiplier
				mov.w   R13,&MPY32_MPY32H		; Load operand 1 High into multiplier
				mov.w   R14,&MPY32_OP2L			; Load operand 2 Low into multiplier
				mov.w   R15,&MPY32_OP2H			; Load operand 2 High, trigger MPY
				mov.w   &MPY32_RES0,R12			; Ready low 16-bits for return
				mov.w   &MPY32_RES1,R13			; Ready high 16-bits for return
				mov.w   #0x0075,R14
				mov.w   #0x00a8,R15
				mov.w   #0x00e7,R12
				mov.w   #0x0038,R13

				call 	#check_update
    			cmp.b 	#0x01,update_avail     	; Compare with #1 value
    			jnz 	_loop      	 			; Repeat loop if not equal
				call 	#decode_update
				jmp 	_loop

;--------------------------------------------------
; Function: 	decode_update
; Description:  decode and update packet stored in rx_buffer
; 				header byte definition: xx         x               xxx           xx
;										opcode  reserved  instruction_length  copy_length
; 										opcode: indicate which update operation.
; 										reserved: not used
; 										instruction_length:  indicate the instruction length at the insert/modify point.
; 										copy_length: indicate the length of instructions(insert/modify) copy to the original space.
; Register used:R10: header
----------------------------
; to do: change op => R9, use a temp register instead.
; so R9 can dedicated to address pointer
; current update, if need to replace last 2 instructions, one empty space will be left.

decode_update:	mov.b	rx_buffer,R10		 	; read header
	        	and.b	#11000000b,R10			; bit masking, clear lower 6 bits to extract opcode
   				cmp.b 	#00000000b,R10    		; Compare with value
    			jz 		modify      	 		; jump if equal
				cmp.b 	#01000000b,R10
    			jz 		delete
				cmp.b 	#10000000b,R10
    			jz 		copy
				cmp.b 	#11000000b,R10
    			jz 		copy
cleanup			mov.b	#0x00,update_avail
				ret

;--------------------------------------------------
; Register used: R10 update packet start address
; 				 R7 optional instruction length
; 				 R6 optional copy length
;				 R9 destination address
;				 R8 length
; 				 R5 data start address
; 				 R4 free address pointer

insert			mov.w	rx_buffer+1,R10			; destination address
	   			mov.b	rx_buffer+3,R9			; length
				mov.b	rx_buffer,R8			; read header
	        	and.b	#00110000b,R8			; bit masking, clear middle 2 bits to extract instruction length
				rra.b	R8
				rra.b	R8
				rra.b	R8
				rra.b	R8
												; copy the instruction from inserting point to
												; new allocated memory space
insert			mov.w 	2(R10),R9				; destination address
				mov.w	4(R10),R8				; length
				mov.w	6(R10),R5				; data start address
				mov.w	free_addr,R4			; load free_addr
insert_l1		dec.w   R7                      ; Decrement R7
				mov.w	0(R9),0(R4)				; copy
				mov.w	#nop,0(R9)
				add.w	#2,R9
				add.w	#2,R4
				cmp		#0,R7
            	jnz     insert_l1               ; copy original instruction done?
												; caculate jump instruction offset and write jump instruction to
												; jump from inserting point to new allocated memory space
				mov.w	free_addr,R13			; R7 temperary free address pointer
				sub.w	R9,R13					; calculate offset
				sub.w	#2,R13
				mov.w	#2,R14
				call 	#div					; R13/R14, result stored in R15
				add.w	jmp_base,R15			; add jump base value
				mov.w	R15,0(R9)
												; check if need to copy to original memory space
insert_l2		mov.w	2(R10),R7				; R7 temprary destination address
				cmp 	#0,R6
				jz     	insert_l3               ; copy new instructions to original memory space done?
				mov.w	0(R5),0(R7)				; copy instruction
				add.w	#2,R5
				add.w	#2,R7
				dec.w	R8
				dec.w	R6
				jmp 	insert_l2
												; copy the rest of instructions to the new allocated memory
insert_l3		dec.w   R8                   	; Decrement R8
				mov.w	0(R5),0(R7)
				add.w	#2,R10
				add.w	#2,R9
				cmp		#0,R7
	        	jnz     update               	; Update done?
	        	sub.w	R9,R8					; Calculate jump back instruction
	        									; should +2 to next instruction, and -2 to calculate offset, cancelled here
	        	mov.w	R8,R13
	        	mov.w	#2,R14
	        	call	#div					; R13/R14, result stored in R15
	        	and.w	#0000001111111111b,R15	; bit masking, clear upper 6 bits
	        	add.w	jmp_base,R15
	        	mov.w	R15,0(R9)
	        	;mov.w	#0x3AE9,0(R9)			; Testing jump
	        	add.w	#2,R9
	        	jmp		#cleanup

;--------------------------------------------------
; modify/replace
modify:

;--------------------------------------------------
; Register used: R10 update packet start address
;				 R9 destination address
;				 R8 length
; 				 R5 data start address
; 				 R4 free address pointer

delete:			mov.w	2(R10),R9				; destination address
    			mov.w	4(R10),R8				; length
    			mov.w	free_addr,R4
				sub.w	R8,R11					; calculate offset
				sub.w	#2,R11
				mov.w	R11,R13
				mov.w	#2,R14
				call 	#div					; R13/R14, result stored in R15
				add.w	jmp_base,R15			; add jump base value
				mov.w	R15,R8
    			jmp 	update_del

copy:			cmp 	#3,R9
    			jnz 	mainloop
    			mov.w	2(R10),R8				; destination address
    			mov.w	4(R10),R7				; length
copy_l1 		dec.w   R7                   	; Decrement R7
				mov.w	0(R10),0(R9)
				add.w	#2,R10
				add.w	#2,R9
				cmp		#0,R7
	        	jnz     copy_l1             	; Done?

;-------------------------------------------------------------------------
; Register used:R10: data start address
;				R9:	 current free address pointer
;				R8:  destination address
;               R7:  update data length
;               R6:  backup size
;---------------------------------------------------------------------------
; current update, if need to replace last 2 instructions, one empty space will be left.
update:

update_ins		dec.w   R7                   	; Decrement R7
				mov.w	0(R10),0(R9)
				add.w	#2,R10
				add.w	#2,R9
				cmp		#0,R7
	        	jnz     update               	; Update done?
	        	sub.w	R9,R8					; Calculate jump back instruction
	       	 									; should +2 to next instruction, and -2 to calculate offset, cancelled here
	        	mov.w	R8,R13
	        	mov.w	#2,R14
	        	call	#div					; R13/R14, result stored in R15
	        	and.w	#0000001111111111b,R15	; bit masking, clear upper 6 bits
	        	add.w	jmp_base,R15
	        	mov.w	R15,0(R9)
	        	;mov.w	#0x3AE9,0(R9)			; Testing jump
	        	add.w	#2,R9
	        	jmp		#cleanup
update_mod		jmp		#cleanup
update_del		jmp		#cleanup
update_copy 	jmp		#cleanup





;-------------------------------------------------------------------------------
; Utility Functions
;---------------------------------------------------------------------

;---------------------------------------------------------------------
; Function: 	wait
; Description:  about 1 sec time delay

wait:       	mov.w   #50000,R5              	; Delay to R15
wait_l1     	dec.w   R5                     	; Decrement R15
            	jnz     wait_l1                 ; Delay over?
            	ret

;---------------------------------------------------------------------
; Function: 	div
; Description:  unsigned 32/16 division, R12|R13 / R14 = R15, Remainder
; in R12
; Register used:R12 is dividend high word
;               R13 is dividend low word
;               R14 is divisor
;               R15 is result
;               R11 is counter

div:        	clr     R15        				;1C
            	clr     R12        				;only 16/16 really
            	mov     #17,R11        			;2C    -4C ENTRY
div_l1     		cmp     R14,R12        			;1C
            	jlo     div_l2        			;2C
            	sub     R14,R12        			;1C    -4C WORST CASE
div_l2    		rlc     R15        				;1C
            	jc      div_l4        			;2C
            	dec     R11        				;1C
            	jz      div_l4        			;2C    -6C ON LAST BIT
            	rla     R13        				;1C
            	rlc     R12        				;1C
            	jnc     div_l1        			;2C
				sub     R14,R12        			;1C
            	setc            				;2C
            	jmp     div_l2        			;2C    -15C WORST
div_l4	    	ret            					;3C

;-------------------------------------------------------------------------------
; Stack Pointer definition
;-------------------------------------------------------------------------------
            	.global __STACK_END
            	.sect   .stack
            
;-------------------------------------------------------------------------------
; Interrupt Vectors
;-------------------------------------------------------------------------------
            	.sect   ".reset"                ; MSP430 RESET Vector
            	.short  RESET
            
