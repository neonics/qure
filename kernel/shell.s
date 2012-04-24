.intel_syntax noprefix

.data
cmdlinelen: .long 0
cmdline: .space 1024
cmdline_tokens: .space 4096
insertmode: .byte 1
cursorpos: .long 0
.text
.code32

shell:	push	ds
	pop	es
	PRINTLNc 10, "Press ^D or type 'quit' to exit shell"

start$:
	PRINT "> "
	mov	dword ptr [cursorpos], 0
	mov	dword ptr [cmdlinelen], 0

0:
	call	print_cmdline$

	mov	edi, offset cmdline
	add	edi, [cursorpos]

	xor	ax, ax
	call	keyboard
	.if 0
	pushcolor 10
	push	ax
	mov	dx, ax
	call	printhex4
	mov	al, ' '
	call	printchar
	mov	al, dl
	call	printchar
	mov	al, ' '
	call	printchar
	pop	ax
	popcolor
	.endif

	cmp	ax, K_ESC
	jz	clear$

	cmp	ax, K_ENTER
	jz	enter$

	cmp	ax, K_BACKSPACE
	jz	bs$

	cmp	ax, K_LEFT
	jz	left$
	cmp	ax, K_RIGHT
	jz	right$

	cmp	ax, K_INSERT
	jz	toggleinsert$

	cmp	al, 127
	jae	0b	# ignore
	cmp	al, 32
	jb	0b	# ignore
	
1:	#cmp	byte ptr [insertmode], 0
	#jz	insert$
	# overwrite
#insert$:
	# overwrite
	cmp	[cmdlinelen], dword ptr 1024-1	# check insert
	# beep
	jb	1f	
	# beep
	jmp	0b
1:	
	cmp	byte ptr [insertmode], 0
	jz	1f
	# insert
	push	edi
	mov	edi, [cursorpos]
	mov	ecx, [cmdlinelen]
	sub	ecx, edi
	add	edi, offset cmdline
	mov	esi, edi
	inc	edi
	rep movsb
	pop	edi
1:	# overwrite
	stosb
	inc	dword ptr [cursorpos]
	inc	dword ptr [cmdlinelen]

	jmp	0b

enter$:	
	PRINT_START
	add	edi, [cursorpos]
	add	edi, [cursorpos]
	xor	es:[edi + 1], byte ptr 0xff
	PRINT_END
	call	newline

	xor	ecx, ecx
	mov	[cursorpos], ecx
	xchg	ecx, [cmdlinelen]
	or	ecx, ecx
	jz	start$
	PRINTc 9, "CMDLINE: \""
	mov	esi, offset cmdline
	call	nprint
	PRINTLNc 9, "\""
	mov	edx, ecx
	call	printhex8
	call	newline

	mov	edi, offset cmdline_tokens
	mov	esi, offset cmdline
	#mov	ecx, [cmdlinelen]
	call	tokenize
	mov	ebx, edi
	mov	esi, offset cmdline_tokens
	call	printtokens

	jmp	start$

bs$:	
	push	edi
	cmp	edi, offset cmdline 
	jbe	0b
	cmp	edi, [cmdlinelen]
	jz	1f
	mov	esi, edi
	dec	edi
	mov	ecx, 1024 + offset cmdline
	sub	ecx, esi
	jz	2f
	rep	movsb
2:	pop	edi


1:	dec	dword ptr [cursorpos]
	jns	1f
	printc 4, "Error: cursorpos < 0"
1:
	dec	dword ptr [cmdlinelen]
	jns	1f
	PRINTlnc 4, "Error: cmdlinelen < 0"
1:	jmp	start$

left$:	dec	dword ptr [cursorpos]
	jns	start$
	inc	dword ptr [cursorpos]
	jmp	start$

right$:	mov	eax, [cursorpos]
	cmp	eax, [cmdlinelen]
	jae	start$
	inc	dword ptr [cursorpos]
	jmp	start$

clear$:	mov	al, ' '
	mov	ecx, [cmdlinelen]
1:	call	printchar
	loop	1b
	print "CLEAR"
	jmp	start$

toggleinsert$:
	xor	byte ptr [insertmode], 1
	jmp	start$

# destroys: ecx, esi, ebx
print_cmdline$:
	push	esi
	push	ecx
	push	ebx


	PRINT_START
	push	edi

	mov	ebx, edi
	mov	ecx, [cmdlinelen]
	or	ecx, ecx
	jz	2f
	mov	esi, offset cmdline

1:	lodsb
	stosw
	loop	1b

2:	mov	al, ' '
	stosw
	stosw

	add	ebx, [cursorpos]
	add	ebx, [cursorpos]
	xor	es:[ebx+1], byte ptr 0xff

	pop	edi
	PRINT_END

	pop	ebx
	pop	ecx
	pop	esi

	ret

