.intel_syntax noprefix

LIBC_DEBUG = 1

# NULL-base (flat cs/ds)
.macro DEFSTUB name, code_label=0
  .ifnc \code_label,0
	_c_\code_label:
  .else
	_c_\name:
  .endif
		printc 0xb0, "\name";
		int 3
		pushfd
#		or	dword ptr [esp], 1 << 8 # trap flag
		popfd
		retf
1:	# in flat cs
		ret
.endm



.data SECTION_DATA_BSS	# WARNING: singleton
proc_esp:	.long 0
proc_ebp:	.long 0

.text32

# see elf.s, find_symbol: scans _c_ prefixes - for any lib, for now.

_c___main:
	mov	[proc_esp], esp
	mov	[proc_ebp], ebp

	.if LIBC_DEBUG
		#ENTER_CPL0

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
		ENTER_CPL0
		printc	0xb0, "exit "
		mov	edx, eax
		call	printdec32
	.endif
	mov	esp, [proc_ebp]
	pop	ebp
	ret

_c_hello:
	printlnc 0xb0, "HELLO!"
	ret

_c_malloc:
	ENTER_CPL0
	printlnc 0xb0, "malloc"
	ret

_c_puts:
	printc 0xb0, "puts:"
	push edx;
	mov edx, [esp+4]; DEBUG_DWORD edx,"ret"
	mov edx, [esp+8]; DEBUG_DWORD edx,"arg"
	pop edx
	pushd [esp + 4]# + SETREGS_STACK_SIZE]
	call	_s_println
#	pushfd;ord [esp], 1<<8;popfd
	ret

_c_printf:
	# realign the format string:
#	push edx; GDT_GET_BASE edx, ds; sub [esp+8+SETREGS_STACK_SIZE], edx; pop edx
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
	jmp	printf


_c_asnprintf:
	printlnc 0xb0, "asnprintf"
	ret

_c_lseek:
	ENTER_CPL0
	printlnc 0xb0, "lseek"
	ret

_c_open:
	ENTER_CPL0
	printlnc 0xb0, "open"
	ret

_c_perror:
	ENTER_CPL0
	.if LIBC_DEBUG
		printlnc 0xb0, "perror"
	.endif
	push	dword ptr [esp+4]
	push	word ptr 12
	call	_s_printlnc
	ret

_c_read:
	ENTER_CPL0
	printlnc 0xb0, "read"
	ret

# cygwin1.dll / ansi
# cygwin1.dll:
DEFSTUB "_dll_crt0@0", _dll_crt0	# @ invalid mnemonic on ELF targets
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

