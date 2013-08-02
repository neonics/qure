.intel_syntax noprefix

LIBC_DEBUG = 1

# NULL-base (flat cs/ds)
.macro DEFSTUB name
	_c_\name:
		call	setregs$
		printc 0xb0, "\name";
		int 3
		pushfd
#		or	dword ptr [esp], 1 << 8 # trap flag
		popfd
		retf
1:	# in flat cs
		call	restoreregs$
		ret
.endm

SETREGS_STACK_SIZE = 16

# modifies stack: esp:[ret] to [ret][es][ds][base][cs]
setregs$:
	sub	esp, 12
	pushd	[esp+12]	# copy ret
	push	eax
	mov	[esp + 8], es
	mov	[esp +12], ds
	mov	[esp +20], cs
	mov	eax, ds
	add	eax, SEL_ring0CS - SEL_ring0CSf
	mov	ds, eax
	mov	es, eax
	GDT_GET_BASE eax, SEL_compatCS
	mov	[esp+16], eax
	sub	[esp+4], eax	# adjust ret offset
	pop	eax
	pushd	cs
	addd	[esp], SEL_ring0CS - SEL_ring0CSf
	pushd	offset 2f
#	int 3
	#DEBUG "retf1"
	retf
2:	# in ds-rel cs


	.if LIBC_DEBUG > 1
	push ebp; lea ebp, [esp+4]
	DEBUG_DWORD [ebp],"ret"
	DEBUG_DWORD [ebp+4],"es"
	DEBUG_DWORD [ebp+8],"ds"
	DEBUG_DWORD [ebp+12],"base"
	DEBUG_DWORD [ebp+16],"cs"
	pop ebp
	.endif
#	int 3

	ret

restoreregs$:
	.if LIBC_DEBUG > 1
		DEBUG "restoreregs"
		push ebp; lea ebp, [esp+4]
		DEBUG_DWORD [ebp],"ret"
		DEBUG_DWORD [ebp+4],"es"
		DEBUG_DWORD [ebp+8],"ds"
		DEBUG_DWORD [ebp+12],"base"
		DEBUG_DWORD [ebp+16],"cs"
		DEBUG_DWORD [ebp+20],"libret"
		pop ebp
		#int 3
	.endif
	mov	ds, [esp + 8]
	mov	es, [esp + 4]
	push	eax
	mov	eax, [esp + 4]	# get ret
	add	[esp + 4 + 12], eax	# update far ret eip
	pop	eax
	add	esp, 12
	retf


.data SECTION_DATA_BSS	# WARNING: singleton
proc_esp:	.long 0
proc_ebp:	.long 0

.text32

# see elf.s, find_symbol: scans _c_ prefixes - for any lib, for now.

_c___main:
	call	setregs$
	mov	[proc_esp], esp
	mov	[proc_ebp], ebp

	.if LIBC_DEBUG
		#call	SEL_kernelCall:0

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
	call	restoreregs$
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
	call	setregs$
	printlnc 0xb0, "HELLO!"
	call	restoreregs$
	ret

_c_malloc:
	call SEL_kernelCall:0
	printlnc 0xb0, "malloc"
	ret

_c_puts:
	#flat, so not needed: push edx; GDT_GET_BASE edx, ds; add [esp+8], edx; pop edx
	call	setregs$
	push edx; GDT_GET_BASE edx, ds; sub [esp+8+SETREGS_STACK_SIZE], edx; pop edx
	printc 0xb0, "puts:"
	pushd [esp + 4 + SETREGS_STACK_SIZE]
	call	_s_println
	call	restoreregs$
#	pushfd;ord [esp], 1<<8;popfd
	ret

_c_printf:
	call	setregs$
	# realign the format string:
	push edx; GDT_GET_BASE edx, ds; sub [esp+8+SETREGS_STACK_SIZE], edx; pop edx
	# the other strings are not realigned!
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
	call	printf
	call	restoreregs$
	ret


_c_asnprintf:
	call	setregs$
	printlnc 0xb0, "asnprintf"
	call	restoreregs$
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

# cygwin1.dll / ansi
# cygwin1.dll:
DEFSTUB "_dll_crt0@0"
DEFSTUB _impure_ptr
DEFSTUB calloc
DEFSTUB cygwin_detach_dll
DEFSTUB cygwin_internal
DEFSTUB dll_dllcrt0
DEFSTUB free
DEFSTUB realloc

# KERNEL32.DLL
DEFSTUB GetModuleHandleA
DEFSTUB GetProcAddress

