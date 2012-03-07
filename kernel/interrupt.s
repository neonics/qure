
.code32
int_count: .long 0
gate_int32:
	push	ax
	push	ds
	
	mov	ax, SEL_flatDS
	mov	ds, ax
	mov	[0xb8000], byte ptr '!'

	pop	ds
	pop	ax
	iret

	cli
	push	es
	push	edi
	push	edx
	push	ax

#	mov	di, SEL_vid_txt
#	mov	es, di
	inc	byte ptr es:[0]
	/*
	xor	edi, edi
	mov	ax, 0xf2<<8 + '!'
	stosw
	mov	edx, [int_count]
	call	printhex8
	inc	dword ptr [int_count]
	*/

	pop	ax
	pop	edx
	pop	edi
	pop	es
	#sti
	iret


