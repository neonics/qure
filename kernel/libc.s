.intel_syntax noprefix

LIBC_DEBUG = 0

.data SECTION_DATA_BSS	# WARNING: singleton
proc_esp:	.long 0
proc_ebp:	.long 0

.text32

_c___main:
	mov	[proc_esp], esp
	mov	[proc_ebp], ebp

	.if LIBC_DEBUG
		call	SEL_kernelCall:0

		printc 0xb0, "MAIN!"
		# remember these for exit..
		DEBUG_DWORD [proc_esp]#esp
		DEBUG_DWORD [proc_ebp]

		push edx
		mov	edx, [proc_esp]
		DEBUG_DWORD [edx], "[esp]"
		mov	edx, [proc_ebp]
		DEBUG_DWORD [edx], "[ebp]"
		pop edx
		call	newline
	.endif
	ret

_c_exit:
	mov	eax, [esp + 4]
	.if LIBC_DEBUG #NOTE! different behaviour! runs in kernel when enabled
		call	SEL_kernelCall:0
		printc	0xb0, "exit "
		mov	edx, eax
		call	printdec32
	.endif
	mov	esp, [proc_ebp]
	pop	ebp
	ret

_c_hello:
	call SEL_kernelCall:0
	printlnc 0xb0, "HELLO!"
	ret

_c_malloc:
	call SEL_kernelCall:0
	printlnc 0xb0, "malloc"
	ret

_c_puts:
	call SEL_kernelCall:0
	printlnc 0xb0, "puts"
	ret

_c_printf:
	call SEL_kernelCall:0
	.if LIBC_DEBUG
		printlnc 0xb0, "printf"
	.if LIBC_DEBUG > 1
		push esi
		mov esi,[esp + 8]
		DEBUG_DWORD esi,"fmt"
		mov esi,[esp + 12]
		DEBUG_DWORD esi,"arg"
		DEBUG_DWORD ebp
		mov esi, [ebp + 0x8]
		DEBUG_DWORD esi,"stackarg"
		mov esi, [ebp + 0xc]
		DEBUG_DWORD esi,"stackarg"
		pop esi
	.endif
	.endif
	jmp	printf


_c_asnprintf:
	call	SEL_kernelCall:0
	printlnc 0xb0, "asnprintf"
	ret

_c_lseek:
	call	SEL_kernelCall:0
	printlnc 0xb0, "lseek"
	ret

_c_open:
	call	SEL_kernelCall:0
	printlnc 0xb0, "open"
	ret

_c_perror:
	call	SEL_kernelCall:0
	.if LIBC_DEBUG
		printlnc 0xb0, "perror"
	.endif
	push	dword ptr [esp+4]
	push	word ptr 12
	call	_s_printlnc
	ret

_c_read:
	call	SEL_kernelCall:0
	printlnc 0xb0, "read"
	ret
