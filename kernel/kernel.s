.intel_syntax noprefix

DEBUG = 2
.include "debug.s"
.include "realmode.s"
###################################
DEFINE = 1
.include "print.s"
.include "pmode.s"
.include "pit.s"
.include "keyboard.s"

###################################

.text
.code32
kmain:
	# we're in flat mode, so set ds so we can use our data..
	mov	ax, SEL_compatDS
	mov	ds, ax

	PRINTc 0x0a "Protected mode initialized."

	COLOR 0xf

	PRINT	"Press key to stop timer."
	mov	ah, 0
	call	keyboard

	call	pit_disable

	call	newline
.if 0
	PRINT	"Press a key to switch to kernel task."
	call	keyboard

	mov	[tss_EIP], dword ptr offset kernel_task
	call	task_switch

	PRINTLNc 0x0c "Back from task"
	jmp	halt
.endif
	call	newline
	PRINT	"Press 'q' or ESC to system halt."

0:	
	mov	ah, 0
	call	keyboard
	mov	dx, ax
	PRINT_START 3
	call	__printhex4
	mov	al, dl
	stosw
	mov	al, ' '
	stosw
	PRINT_END
	
	cmp	al, 'q'
	je	1f
	cmp	ax, K_ESC
	jne	0b
1:

halt:	call	newline
	PRINTc	0xb, "System Halt."
0:	hlt
	jmp	0b


kernel_task:
	PRINTLNc 0x0b "Kernel Task"
	retf


.data
sig:.long 0x1337c0de
.equ KERNEL_SIZE, .
