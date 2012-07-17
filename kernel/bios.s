##############################################################################
## BDA : BIOS DATA AREA ######################################################
##############################################################################
# Memory address: 0000:0400 Size 100h

bios_list_bda:
	push	es

	call	newline
	COLOR	8

	mov	ax, SEL_flatDS
	mov	es, ax

	mov	ax, es:[0x410]	# equipment word
	mov	esi, 0x400
	PRINTc	7, "Serial Ports: "
	mov	dx, ax
	shr	dx, 9
	and	dx, 7
	call	printhex1
	PRINTc	7, ": "

	# 0x00, 0x02, 0x04, 0x06 (int 14h): base io serial
2:	xor	cl, cl
0:	mov	dx, es:[esi]
	or	dx, dx
	jz	1f
	call	printhex4
	PRINTCHAR ' '
1:
	add	esi, 2
	inc	cl
	cmp	cl, 4
	jb	0b
	call	newline
	cmp	esi, 0x400 + 4*2
	jne	0f
	PRINTc	7, "Parallel Ports: "
	mov	dx, ax
	shr	dx, 14
	and	dx, 3
	call	printhex1
	PRINTc	7, ": "
	# 0x08, 0x0a, 0x0c, 0x0e (int 14h): base io parallel
	jmp	2b
0:
	# 0x10: (int 11h) Equipment word
	# bit 0   bootfloppy
	# bit 1   math coprocessor
	# bit 2   ps/2 mouse
	# bit 3   reserved
	# bit 5:4 video mode: 00=ega/later, 01=40x35, 02=80x25, 11=mono 80x25
	# bit 7:6 num floppies
	# bit 8   reserved
	# bit 11:9 num serial ports
	# bit 13:12 reserved
	# bit 15:14 parallel ports
	mov	ax, es:[esi]
	add	esi, 2
	mov	dx, ax
	test	dl, 1
	jz	0f
	PRINTc	10, "BootFloppy "
0:	test	dl, 2
	jz	0f
	PRINTc	11, "MathCopro "
0:	test	al, 4
	jz	0f
	PRINTc	12, "PS/2 Mouse "
0:	shr	dx, 4
	and	dx, 3
	PRINT	"VideoMode: "
	call	printhex1
	call	newline
	mov	dx, ax
	shr	dx, 6
	and	dl, 3
	PRINTc	7, "Floppies: "
	call	printhex1

	mov	dl, es:[0x475]
	PRINTc	7, " Hard Disks: "
	call	printhex2
	call	newline


	xor	edx, edx
	mov	dx, es:[0x413]
	PRINTc	13, "Low Memory Size / EBDA start: "
	shl	edx, 10
	call	printhex8
	call	newline


	mov	dx, es:[0x44a]
	PRINT	"Console Columns: "
	call	printhex4
	mov	dx, es:[0x474]
	PRINT	" Video Rows: "
	call	printhex2

	mov	dx, es:[0x44c]
	PRINT	" Video Page Size: "
	call	printhex4

	mov	dx, es:[0x44e]
	PRINT	" Offset:  "
	call	printhex4
	call	newline

	mov	dx, es:[0x463]
	PRINTc	7, "Display Adapter IO Port: "
	call	printhex4

	mov	edx, es:[0x467]	
	PRINT	" ROM Address: "
	call	printhex4
	PRINTCHAR ':'
	shr	edx, 16
	call	printhex4

	mov	edx, es:[0x4a8]	
	ror	edx, 16
	PRINTc	7, " Video PCB: " # Video Parameter Control Block
	call	printhex4
	PRINTCHAR ':'
	shr	edx, 16
	call	printhex4
	call	newline

	mov	dl, es:[0x477]	
	PRINT	"XT HDD IO Port: "
	call	printhex2

	pop	es
	ret


############################# PMode - Realmode BIOS interface ##############
bios_proxy:
	# dl = the interrupt.
	# call the realmode handler, staying in pmode
	push	ebp
	mov	ebp, esp
	push	eax
	push	edx
	push	edi
	# mov edi, current_screen_pos

	mov	ax, SEL_flatDS
	mov	ds, ax
	and	edx, 0xff
	shl	edx, 2
	mov	edx, [edx]	# load INT handler ptr
	mov	ah, 0xf6
	call	printhex
	PRINTCHARc 0, ':'
	mov	al, ':'
	stosw
	ror	edx, 16
	call	printhex
	ror	edx, 16

	cmp	dx, 0xf000
	LOAD_TXT "Not BIOS call"
	je	0f

	# now, we need to restore the registers, and push the BIOS call
	# address on the stack.
	# We'll just duplicate the call stack, assuming that BIOS
	# functions do not use stack arguments except the flags.
	#(which they dont AFAIK).

	# set up fake call stack for bios function
	mov	ax, [ebp + 4 + 4 + 2]	# low word flags
	push	ax
	push	cs
	push	offset 2f # assumes non-0-based (flat) cs
	# now, in 16 bit code, iret will return us at label 2

	# prepare call structure to jump to 16 bit bios using 32 bit iret:
	mov	eax, [ebp + 4 + 4 + 2]  # flags
	push	eax	
	push	word ptr SEL_biosCS	# selector/ 'segment'
	shr	edx, 16			# offset of function
	push	edx	# offset

	# restore registers:

	mov	edx, [ebp - 20]
	mov	edi, [ebp - 16]
	mov	ax,  [ebp - 12] # ds
	mov	ds, ax
	mov	ax,  [ebp - 10] # es
	mov	es, ax
	mov	esi, [ebp - 8]
	mov	eax, [ebp - 4]
	mov	ebp, [ebp]

	# now use iret to conveniently jump
	iret
.code16
2:	# BIOS should return here in 16 bit CS selector
	# return to 32 bit CS
	push	SEL_compatCS # should be same as in IDT
	push	offset 2f
	retf
.code32
2:	# back in 32 bit, show message:
	mov	ax, SEL_vid_txt
	mov	edi, 2 * ( 1*80 + 0 )
	mov	ax, SEL_compatDS
	mov	ds, ax
	mov	ah, 0xf1
	PRINT "Return from BIOS call"

	pop	edi
	pop	edx
	pop	eax
	pop	ebp
	ret # or iret, depending on how this is called.

