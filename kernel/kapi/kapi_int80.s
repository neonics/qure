.tdata
tls_kapi_cont:	.long 0
tls_kapi_cr3:	.long 0
.tdata_end


kapi_int80_init:
	I "Kernel API"

	mov	[IDT + 0x80*8 + 5], byte ptr (ACC_PR|IDT_ACC_GATE_INT32|ACC_RING3)
	mov	[IDT + 0x80*8 + 2], word ptr SEL_compatCS
	mov	[IDT + 0x80*8 + 0], word ptr (offset kapi_int80_isr-.text)&0xffff
	mov	[IDT + 0x80*8 + 6], word ptr (offset kapi_int80_isr-.text)>>16

	OK
	ret


kapi_int80_isr:
	DEBUG "int80", 0xf0

	.if KAPI_MODE == KAPI_MODE_INT80_STACK
	push	ebp
	lea	ebp, [esp + 4]
	test	byte ptr [ebp + 4], 3	# check CPL
	jz	1f
################
	mov	ebp, [ebp + 12]		# get user esp
	DEBUG_DWORD [ebp]
	push	edx
	mov	edx, [ebp]
	cmp	edx, offset KAPI_NUM_METHODS
	jae	9f
	pushd	[kapi_idx + edx * 4]
	call	_s_print
	mov	edx, [kapi_ptr + edx * 4]
	# TODO: stackarg 
	xchg	edx, [esp]
	mov	ebp, esp
	DEBUG_DWORD [ebp], "calling"
	call	[esp]
	DEBUG "returned"
	add	esp, 4

	jmp	2f
################
1:	
	DEBUG_DWORD [ebp + 0],"eip"
	DEBUG_DWORD [ebp + 4],"cs"
	DEBUG_DWORD [ebp + 8],"eflags"
	DEBUG_DWORD [ebp + 12],"arg0"

	# schedule_task is likely

	push	edx
	mov	edx, [ebp + 12]
	cmp	edx, offset KAPI_NUM_METHODS
	jae	9f
	pushd	[kapi_idx + edx * 4]
	call	_s_print

	push	eax
	mov	eax, [ebp + 0]	# get eip
	mov	[ebp + 12], eax	# overwrite arg0 with original return address
	pop	eax

	mov	edx, [kapi_ptr + edx * 4]
	mov	[ebp], edx	# overwrite eip with the method address
	# now on iret, the method will run, followed by a ret to arg0 (orig eip).
	# ok, works partially, except for cr3 stuff.
	# SOLUTION 1: use a proxy - problem: where to put the original return address/cr3
	# SOLUTION 2: don't do a real iret.
	# SOLUTION 3: use ebp to point to stack - change stackmethods to register calling.
	# current paging methods don't swap cr3, they could.
	# not sure WHY a page fault occurs, since the call is from ring0.
	# possible reason: other tasks run at ring0 with different cr3.
	# solution: don't use cr3 swapping on RING0 tasks.
	# problem: kernel threads cannot be isolated using paging.

	# abuse the task tls
	push	eax
	call	tls_get
	mov	edx, [ebp + 12]	# get the continuation address
	mov	[eax + tls_kapi_cont], edx
	mov	edx, cr3
	mov	[eax + tls_kapi_cr3], edx
	mov	[ebp + 12], dword ptr offset kapi_int80_cont
	pop	eax

	pop	edx
################
2:	pop	ebp
	.else
	DEBUG_DWORD eax
	.endif

	iret

9:	printc 4, "KAPI call: unknown method number: "
	call	printhex8
	pop	edx
	jmp	2b


kapi_int80_cont:
	sub	esp, 4
	push	eax
	call	tls_get
	mov	eax, [eax + tls_kapi_cr3]
	mov	cr3, eax
	pop	eax
