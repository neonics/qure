###############################################################################
# Kernel API 
.intel_syntax noprefix

.if DEFINE


	# multiple object files:
	# 1) _KAPI_COUNTER gets reset
	# 2) data sections are not merged.

.section .kapi$idx
kapi_idx:
.section .kapi$ptr
kapi_ptr:
.section .kapi$str
kapi_str:
.section .kapi$arg
kapi_arg:
.text32

# defined in kernel.link
#KAPI_NUM_METHODS = ( offset data_kapi_idx_end - offset kapi_idx ) / 4

KAPI_PAGE	= (0xffc00000>>12) + 1023
KAPI_BASE	= 4096 * KAPI_PAGE
.endif

.ifndef _KAPI_COUNTER
_KAPI_COUNTER = 0
.endif

.ifndef __KAPI_DECLARED

KAPI_MODE_PAGE_TASK	= 1
KAPI_MODE_PAGE_INT	= 2
KAPI_MODE_PAGE_CALLGATE	= 3
KAPI_MODE_INT80_STACK	= 4
KAPI_MODE_INT80_EAX	= 5
KAPI_MODE_SYSENTER	= 10

#KAPI_MODE = KAPI_MODE_PAGE_TASK	# ok
KAPI_MODE = KAPI_MODE_PAGE_INT		# ok
#KAPI_MODE = KAPI_MODE_PAGE_CALLGATE	# doesn't work
#KAPI_MODE = KAPI_MODE_SYSENTER	# sysexit still needs work
#KAPI_MODE = KAPI_MODE_INT80_STACK


.macro KAPI_DECLARE name, stackargs=0
	_PTR = .# (. - .text)	# get .text offset
	.section .kapi$str
	999: .asciz "\name"
	.section .kapi$idx
	.long 999b
	.section .kapi$ptr
	.long	_PTR
	.section .kapi$arg
	.long	\stackargs
  .if KAPI_MODE == KAPI_MODE_PAGE_CALLGATE
	.section .kapi$ldt
	DEFCALLGATE SEL_compatCS, _PTR, 3, \stackargs
  .endif
	.offset _KAPI_COUNTER	# absolute section (aka .struct _KAPI_COUNTER)
	KAPI_\name: #= _KAPI_COUNTER
	.global KAPI_\name
	.print "Declare Kernel API: \name"
	_KAPI_COUNTER = _KAPI_COUNTER + 1
	.text32
.endm

.macro KAPI_CALL name
	.if KAPI_MODE <= KAPI_MODE_PAGE_CALLGATE
	call	SEL_kapi:KAPI_\name
	.elseif KAPI_MODE == KAPI_MODE_SYSENTER
	KAPI_SYSENTER \name
	.elseif KAPI_MODE == KAPI_MODE_INT80_EAX
	mov	eax, offset KAPI_\name
	int	0x80
	.elseif KAPI_MODE == KAPI_MODE_INT80_STACK
	pushd	offset KAPI_\name
	int	0x80
	.else
	.error "Unknown KAPI_MODE"
	.endif
.endm

.endif

.if DEFINE

KAPI_PF_DEBUG = 0
.if	KAPI_MODE == KAPI_MODE_PAGE_TASK
.include "kapi/kapi_page_task.s"
.elseif	KAPI_MODE == KAPI_MODE_PAGE_INT
.include "kapi/kapi_page_int.s"
.elseif	KAPI_MODE == KAPI_MODE_PAGE_CALLGATE
.include "kapi/kapi_page_callgate.s"
.elseif	KAPI_MODE == KAPI_MODE_SYSENTER
.include "kapi/kapi_sysenter.s"
.elseif	KAPI_MODE == KAPI_MODE_INT80_EAX || KAPI_MODE == KAPI_MODE_INT80_STACK
.include "kapi/kapi_int80.s"
.else
.error "Unknown KAPI_MODE"
.endif


kapi_init:

.if KAPI_MODE == KAPI_MODE_SYSENTER
	call	kapi_init_sysenter
	ret
.elseif KAPI_MODE <= KAPI_MODE_PAGE_CALLGATE

	call	kapi_map_base
	mov	eax, KAPI_BASE
	GDT_SET_BASE SEL_kapi, eax


	################################
	.if KAPI_MODE == KAPI_MODE_PAGE_TASK
	call	kapi_init_page_task
	.elseif KAPI_MODE == KAPI_MODE_PAGE_INT
	call	kapi_init_page_int
	.elseif KAPI_MODE == KAPI_MODE_PAGE_CALLGATE
	call	kapi_init_page_callgate
	.else
	.error "unknown KAPI_MODE_PAGE*"
	.endif
	ret
.elseif KAPI_MODE == KAPI_MODE_INT80_EAX || KAPI_MODE == KAPI_MODE_INT80_STACK
	call	kapi_int80_init
	ret
.else
.error "Unknown KAPI_MODE"
.endif


# ensure the KAPI_BASE page 4mb range has a page table
kapi_map_base:
	mov	esi, [page_directory]
	mov	eax, [esi + 4*(KAPI_BASE >> 22)]
	or	eax, eax
	jnz	1f

	#call	malloc_page_phys
	mov	esi, cr3
	call	paging_alloc_page_idmap
	jc	9f
	#call	paging_idmap_page_pt_alloc	# make the page table accessible
	#jc	9f
	or	eax, PDE_FLAG_RW | PDE_FLAG_P
	mov	esi, [page_directory]
	mov	[esi + 4*(KAPI_BASE>>22)], eax
	and	eax, 0xfffff000
1:	ret
9:	printlnc 4, "kapi init error"
	int 3
	ret


##############################################################################

cmd_kapi:
	mov	ecx, offset KAPI_NUM_METHODS
	mov	edx, ecx
	print "Kernel Api Methods: "
	call	printdec32
	call	newline

	mov	esi, offset kapi_idx
	xor	ebx, ebx

0:	mov	edx, ebx	# _KAPI_COUNTER
	call	printhex8
	call	printspace

	mov	edx, [esi + _KAPI_IDX_SIZE]	# read kapi_ptr
	call	printhex8
	call	printspace

	lodsd
	pushd	eax
	call	_s_println

	inc	ebx
	loop	0b
	ret


cmd_kapi_test:
	.if 1
	KAPI_CALL fs_openfile
	.else
	push	fs
	mov	eax, SEL_flatDS
	mov	fs, eax
	mov	eax, KAPI_BASE + 10
	DEBUG_DWORD eax
	mov	eax, fs:[eax]
	DEBUG_DWORD eax
	pop	fs
	.endif
	ret
.endif
