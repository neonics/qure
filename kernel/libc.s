.intel_syntax noprefix

.data SECTION_DATA_BSS	# WARNING: singleton
proc_esp:	.long 0
proc_ebp:	.long 0

.text32


_c___main:	printlnc 0xb0, "MAIN!"
		# remember these for exit..
		mov	[proc_esp], esp
		mov	[proc_ebp], ebp
		DEBUG_DWORD esp
		DEBUG_DWORD ebp
		ret

_c_exit:	printc 0xb0, "exit" 
		mov	edx, [esp + 4]
		call	printdec32
		DEBUG_DWORD esp
		DEBUG_DWORD ebp
		mov	esp, [proc_ebp]
		DEBUG_DWORD esp
		leave
		DEBUG "leave:"
		DEBUG_DWORD ebp
		DEBUG_DWORD esp
		# we're at the main level, now do another leave
		add	esp, 4
		leave
		call	newline
		DEBUG "leave:"
		DEBUG_DWORD ebp
		DEBUG_DWORD esp
		ret

_c_hello:	printlnc 0xb0, "HELLO!"
		ret

_c_malloc:	printlnc 0xb0, "malloc"
		ret

_c_puts:	printlnc 0xb0, "puts"
		ret

_c_printf:	printlnc 0xb0, "printf"
jmp printf
		DEBUG "format string:"
		mov	esi, [esp + 4]
		call	print
		DEBUG "arg1:"
		mov	esi, [esp + 8]
		call	println

		push	ebp
		lea	ebp, [esp + 8]
		mov	esi, [ebp]
		add	ebp, 4
	0:	lodsb
		or	al, al
		jz	0f
		cmp	al, '\n'
		jnz	1f
		call	newline
		jmp	0b
	#############################
	1:	cmp	al, '%'
		jnz	1f
		lodsb
		or	al, al
		jz	0f
		cmp	al, '%'
		jz	1f
		##################
		cmp	al, 's'
		jnz	2f
		push	esi
		mov	esi, [ebp]
		add	ebp, 4
		call	print
		pop	esi
		jmp	0b
	2:	printc 4, "unknown format: "
		add	ebp, 4
	#############################
	1:	call	printchar
		jmp	0b

	0:	pop	ebp
		ret

_c_asnprintf:	printlnc 0xb0, "asnprintf"
		ret

_c_lseek:	printlnc 0xb0, "lseek"
		ret

_c_open:	printlnc 0xb0, "open"
		ret

_c_perror:	printlnc 0xb0, "perror"
		mov	esi, [esp + 4]
		mov	ah, 12
		call	println
		ret

_c_read:	printlnc 0xb0, "read"
		ret
