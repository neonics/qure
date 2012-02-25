.code16
printhex8:
	push	ax
	push	cx
	push	edx
	mov	cx, 8
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jb	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loopnz	0b
	pop	edx
	pop	cx
	pop	ax
	ret

.code32
printhex8_32:
	push	eax
	push	ecx
	push	edx
	mov	ecx, 8
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jb	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loopnz	0b
	pop	edx
	pop	ecx
	pop	eax
	ret

####################

.global cls_32
cls_32:
	mov	di, SEL_gfx_txt
	mov	es, di
	xor	edi, edi
	mov	ecx, 80 * 25 # 7f0
	rep	stosw
	xor	edi, edi
	ret


# arg: es:di screen ptr
# arg: ax: number
# uses: ax, dx, di

# arg: dx
.global printhex2_32
printhex2_32:
	push	ax
	push	cx
	push	dx
	mov	cx, 2
	shl	dx, 8
	jmp	0f
.global printhex_32
printhex_32:
	push	ax
	push	cx
	push	dx
	mov	cx, 4
0:	rol	dx, 4
	mov	al, dl
	and	al, 0xf
	cmp	al, 10
	jb	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loopnz	0b

	add	di, 2
	pop	dx
	pop	cx
	pop	ax
	ret

.macro PRINTHEX_32 r
	.if \r eq dx
	call	printhex_32
	.else
	push	dx
	mov	dx, \r
	call	printhex_32
	pop	dx
	.endif
.endm


.global newline_32
newline_32:
	push	ax
	push	dx
	mov	ax, di
	mov	dx, 160
	div	dl
	mul	dl
	add	ax, dx
	mov	di, ax
	pop	dx
	pop	ax
	ret

.global println
.if !1337
0:	call	newline_32
	ret
println_32:
	push 	offset 0b
	jmp	print_32
.else
println_32:
	call	print_32
	jmp	newline_32
.endif

.global print_32
0:	stosw
print_32:
	lodsb
	test	al, al
	jnz	0b
	ret


# DO NOT USE IN bootloader.s BEFORE SECTOR 1!!
.macro	PRINT_32 a
	.data
	9: .asciz "\a"
	.text
	push	esi
	mov	esi, offset 9b
	call	print_32
	pop	esi
.endm

.macro PRINTLN_32 a
	.data
	9: .asciz "\a"
	.text
	push	esi
	mov	esi, offset 9b
	call	println_32
	pop	esi
.endm

.macro PRINTc_32 color, str
	push	ax
	mov	ah, \color
	PRINT_32 "\str"
	pop	ax
.endm

.macro PRINTLNc_32 color, str
	push	ax
	mov	ah, \color
	PRINTLN_32 "\str"
	pop	ax
.endm
####################



# little print macro
.macro PH8 m, r
	push	edx
	.if \r != edx
	mov	edx, \r
	.endif
	push	ax
	mov	ah, 0xf0
	PRINT "\m" 
	call	printhex8
	add	di, 2
	pop	ax
	pop	edx
.endm

.macro DBGSO16 msg, seg, offs
	mov	ah, 0xf0
	PRINT	"\msg"
	mov	dx, \seg
	call	printhex
	mov	es:[di-2], byte ptr ':'
	mov	dx, \offs
	call	printhex
.endm

.macro DBGSTACK16 msg, offs
	PRINT	"\msg"
	mov	bp, sp
	mov	dx, [bp + offs]
	call	printhex
.endm


# Assuming es = SEL_vid_txt
.macro SCREEN_INIT
	mov	di, SEL_vid_txt
	mov	es, di
	xor	edi, edi
.endm
.macro SCREEN_OFFS x, y
	o =  2 * ( \x + 80 * \y )
	.if o == 0
	xor	edi, edi
	.else
	mov	edi, o
	.endif
.endm



.code16
