# Intel i686+ SYSENTER/SYSEXIT 32-bit Kernel API.
#
# Intel invented SYSENTER/SYSEXIT - supported on AMD - for 32 bit PMode.
#	wrmsr	0x174, [kernel_cs]
#	wrmsr	0x175, [kernel_esp]
#	wrmsr	0x176, [kernel_eip]
# AMD invented SYSCALL/SYSEXIT - supported on Intel - for 64 bit PMode.
#	wrmsr	0xc0000081, [userCS][kernelCS][eip]	# STAR
#	wrmsr	0xc0000082, [kernel RIP 64bit]	# LSTAR
#	wrmsr	0xc0000083, [kernel RIP compat]	# CSTAR
#	wrmsr	0xc0000084, [32 bit: SYSCALL flag mask] # SFMASK
#	syscall: in: ecx=ret eip


# This file implements the 32-bit variant.
# 
# Descriptor Requirements:
# SEL_x		CPL0 Code	(kernel)
# SEL_x+8	CPL0 Stack	(kernel)
# SEL_x+16	CPL3 Code	(user)
# SEL_x+24	CLP3 Stack	(user)

IA32_SYSENTER_CS=0x174	
IA32_SYSENTER_ESP=0x175	
IA32_SYSENTER_EIP=0x176	

kapi_init_sysenter:
	print "KAPI sysenter: "
	mov	eax, 1
	cpuid
	test	edx, 1<<5
	jz	1f

	GDT_GET_BASE ebx, cs
	# intel i686+ (amd compat)
	# WRMSR: MSR[ecx] = edx:eax
	xor	edx, edx	# high 32 bit
	mov	eax, SEL_sysCS
	mov	ecx, IA32_SYSENTER_CS
	wrmsr
	mov	eax, [kernel_sysenter_stack]
	add	eax, ebx	# make flat
	mov	ecx, IA32_SYSENTER_ESP
	wrmsr
	mov	eax, offset kapi_sysenter_handler
	add	eax, ebx	# convert to flat
	mov	ecx, IA32_SYSENTER_EIP
	wrmsr
	OK
	call	kapi_sysenter_debug
	ret
	# sysenter; in: ecx=stack, edx=eip
1:	println "No MSR"
	jmp halt
	ret


.macro KAPI_SYSENTER name
	push	edx	# preserve
	push	ecx	# preserve
	pushd	KAPI_\name
	# unprivileged return info
##	GDT_GET_BASE edx, cs	# edx rel to SEL_usrCS, which is flat
	mov	ecx, esp
#	add	ecx, edx	# flat
	DEBUG_DWORD (offset 567f)
##	add	edx, offset 567f
	mov	edx, offset 567f
	DEBUG_DWORD edx
	DEBUG "SYSENTER \name", 0xf0
	sysenter	# does not do anything with ecx, edx.
567:	# get our proper cs
	#pushd	SEL_ring2CS
	#pushd	offset 567f
567:
mov	ecx, SEL_ring3DS
mov	ss, ecx
	DEBUG "SYSEXIT", 0xf0
	pop	ecx	# get ecx modified by method
	pop	edx	# get edx modified by method
.endm



kapi_sysenter_handler:
	# The kernel uses CS with base != 0, so in order to call methods,
	# we'll need to set up cs properly.
	push	cs
	pushd	SEL_compatCS
	pushd	offset 1f
	retf
1:
DEBUG_DWORD esp
	push	eax
	DEBUG "sysenter"
	mov	eax, cr3
	DEBUG_DWORD eax
	xchg	eax, [esp]
	push	eax
	mov	eax, [page_directory_phys]
	DEBUG_DWORD eax
	mov	cr3, eax
	pop	eax


	DEBUG_WORD ds
	DEBUG_WORD cs
	DEBUG_DWORD esp
	# ebp is setup in KAPI_SYSENTER
	DEBUG_DWORD ecx, "user esp"
	DEBUG_DWORD edx, "user eip"
	DEBUG_DWORD [ecx], "kapi"
	# perform the call
	cmp	[ecx], dword ptr offset KAPI_NUM_METHODS
	jae	9f

DEBUG "copy stackargs"
	push_	ecx edx

	# copy stack args
	mov	edx, [ecx]
	mov	edx, [kapi_arg + edx * 4]
	shl	edx, 2
	jz	1f
DEBUG_DWORD edx, "stackarg size"
	sub	esp, edx
	push_	edi esi
	lea	edi, [esp + edx]	# -4?
	lea	esi, [ecx + 12]	# skip KAPI_name, ecx, edx
	push	ecx
	mov	ecx, edx#[kapi_arg + edx]
	shr	ecx, 2
	std
	rep	movsd
	cld
	pop	ecx

	# adjust the user stack: pop the method stackargs, and move KAPI_name,
	# ecx, and edx to the stack top.
	#
	# PRE:		POST:
	#
	# stackargN	edx
	# stackarg0	ecx
	# edx		KAPI_name
	# ecx
	# KAPI_name
	# copy the bottom 3 dwords to the top of the stackargs
	mov	edi, [ecx + 4]	# get pushed ecx
	mov	[ecx + 4 + edx], edi	
	mov	edi, [ecx + 8]	# get pushed edx
	mov	[ecx + 8 + edx], edi	
	mov	edi, [ecx + 0]
	mov	[ecx + 0 + esi], edi
	lea	ecx, [ecx + edx]	# pop the stackargs from user stack.
2:	pop_	esi edi

1:	mov	edx, [ecx]
	add	ecx, 4			# pop KAPI_name from user stack
	# update our copy of ecx
DEBUG_DWORD ecx
	mov	[esp + 4], ecx	# 4: edx
	# esp points to local stackargs

DEBUG "calling"
DEBUG_DWORD esp
	# simulate a call without using a register
	push	dword ptr offset 1f
	pushd	[kapi_ptr + edx * 4]
mov edx, [esp]
DEBUG_DWORD edx
	mov	edx, [ecx + 4]	# restore pre-KAPI_SYSENTER edx
	mov	ecx, [ecx + 0]	# restore pre-KAPI_SYSENTER ecx
	ret	# call the method, which will pop the local stackargs
1:	DEBUG "called"
DEBUG_DWORD esp
	# esp now points to our edx, ecx backup
	# update ecx, edx on the user stack
	push	ebp
	mov	ebp, [esp + 8]	# get ecx = user stack
DEBUG_DWORD ebp
	mov	[ebp + 0], ecx	# overwrite return ecx
	mov	[ebp + 4], edx	# overwrite return edx
	pop	ebp

	# restore the parameters for sysexit: user eip, user esp
	# user esp (ecx) has been adjusted to point to ecx, edx,
	# and stackargs are removed.
	pop_	edx ecx

0:	# we're almost ready to return. CR3, SEL_sysCS is still on stack:
DEBUG_DWORD esp
	xchg	eax, [esp]
	mov	cr3, eax
	pop	eax

	push	eax
	GDT_GET_BASE eax, cs
	add	eax, offset 1f
	xchg	eax, [esp]
	push ebp; lea ebp, [esp+4]; DEBUG_DWORD [ebp],"o"; DEBUG_DWORD [ebp+4],"cs";pop ebp

	# do the debug here before cs is swapped.
	DEBUG "sysexit"
	DEBUG_DWORD ecx
	DEBUG_DWORD edx

	retf
1:	# we're back with the original CS, though, the trickery may not be needed.

	pushf
	push edx
	GDT_GET_BASE edx, ds
	add	ecx, edx	# make stack flat so accessible
	pop edx
	popf

	sysexit		# in: ecx=esp, edx=eip
	# sysexit:
	#  mov cs, [cs + 16]
	#  mov ss, [cs + 24]
	#  mov esp, ecx
	#  mov eip, edx
9:	printc 4, "sysenter: invalid function: "
	DEBUG_DWORD [ecx]
	call	newline
	add	ecx, 4
	#mov	eax, -1
	stc
	jmp	0b



kapi_sysenter_debug:
	push_	ecx edx eax
	mov	ecx, IA32_SYSENTER_CS
	rdmsr
	DEBUG_WORD ax, "SYSENTER_CS"
	inc	ecx
	rdmsr
	DEBUG_DWORD eax, "SYSENTER_ESP"
	inc	ecx
	rdmsr
	DEBUG_DWORD eax, "SYSENTER_EIP"
	pop_	eax edx ecx
	ret
