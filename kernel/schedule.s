.intel_syntax noprefix

SCHEDULE_DEBUG = 1

.struct 0
task_addr:	.long 0	# eip of task
task_arg:	.long 0	# value to be passed in edx
task_label:	.long 0	# name of task (for debugging)
task_registrar:	.long 0	# address from which schedule_task was called (for debugging when task_addr=0)
.data
schedule_sem: .long -1	# -1: scheduling disabled; locked by: 1=schedule 2=schedule_task
.data SECTION_DATA_BSS
scheduled_tasks: .long 0
SCHEDULE_STRUCT_SIZE = 12
.text32

# This method is called immediately after an interrupt has handled,
# and it is the tail part of the irq_proxy.
schedule:
	push	ebp
	mov	ebp, esp
	push	offset schedule	# for stack debugging
	push	ds
	push	es
	push	eax
	push	edx
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax

	call	get_scheduled_task$	# out: eax, edx
	jc	9f

	# keep interrupt flag as before IRQ
	.if 1
	# access EFLAGS: ebp + 4 -> eip:cs:eflags (+12 then ->eflags)
	# unless SCHEDULE_IRET = 0: a return ptr then preceeds eip on stack.
	test	word ptr [ebp + 12 + 4*(SCHEDULE_IRET-1)], 1 << 9 # irq flag;
	jz	1f
	sti
1:
	.else
	sti
	.endif

	pushad		# assume the task does not change segment registers
	call	eax	# in: edx;
	popad

	.if 1
	mov	eax, edx
	call	mfree
	.endif

9:	pop	edx
	pop	eax
	pop	es
	pop	ds
	add	esp, 4	# pop offset schedule (as iret has no arguments)
	pop	ebp
.if SCHEDULE_IRET
	iret
.else
	ret
.endif


# nr: 3 = failed to acquire lock
# nr: 2 = lock success, executing task
# nr: 1 = lock success, no task
# nr: 0 = no data
.macro SCHED_UPDATE_GRAPH nr
.if SCHEDULE_DEBUG
	push	eax
	.ifc al,\nr
	movzx	eax, \nr
	.else
	mov	eax, \nr
	.endif
	call	sched_update_graph
	pop	eax
.endif
.endm


# out: eax = task ptr
# out: edx = task arg
# out: esi = task label
# out: CF = 1: no task or cannot lock task list
get_scheduled_task$:
	# schedule_task does spinlock, so we don't, as this
	# method is called regularly.
	mov	eax, 1
	xchg	[schedule_sem], eax
	or	eax, eax
	jnz	9f	# task list locked - abort.

	push	ebx
	push	ecx
########
	# one-shot first-in-list
	mov	ebx, [scheduled_tasks]
	or	ebx, ebx
	jz	1f
	xor	ecx, ecx	# index
########
0:	mov	eax, -1
	xchg	eax, [ebx + ecx + task_addr]
	mov	edx, [ebx + ecx + task_arg]	# ptr
	#mov	esi, [ebx + ecx + task_label]	# label
	cmp	eax, -1
	jnz	0f
########
	add	ecx, SCHEDULE_STRUCT_SIZE
	cmp	ecx, [ebx + array_index]
	jb	0b
########
1:	SCHED_UPDATE_GRAPH 2
	stc
	jmp	1f	# no task
0:	## null check
	or	eax, eax
	jnz	2f
	printlnc 4, "ERROR: scheduled task address NULL: registrar: "
	push	edx
	mov	edx, [ebx + ecx + task_registrar]
	call	printhex8
	pop	edx
	mov	eax, edx
	call	mfree
	SCHED_UPDATE_GRAPH 5
	stc
	jmp	1f
2:	##
	SCHED_UPDATE_GRAPH 3
	clc
########
1:	pop	ecx
	pop	ebx

	mov	dword ptr [schedule_sem], 0	# we have lock so we can write.
	ret

9:	mov	[schedule_sem], eax	# ok since nonzero (Potential race condition!)
	SCHED_UPDATE_GRAPH 1
	stc
	ret



.if SCHEDULE_DEBUG
.data SECTION_DATA_BSS
sched_graph: .space 80	# scoller
.data
sched_graph_symbols:
	.byte ' ', 0
	.byte '-', 0x4f
	.byte '-', 0x3f
	.byte '+', 0x2f
	.byte 'S', 0x1f
	.byte 'x', 0xf4
	.byte '?', 0x0f
	.byte '?', 0x0f
.text32
# in: al = nr
# destroys: eax
sched_update_graph:
	push	ecx
	push	esi
	push	edi
	mov	ecx, 79
	mov	edi, offset sched_graph
	mov	esi, offset sched_graph + 1
	rep	movsb
#	stosb
	mov	byte ptr [sched_graph + 79], al
	PUSH_SCREENPOS
	PRINT_START
	mov	esi, offset sched_graph
	xor	edi, edi
	xor	eax, eax
	mov	ecx, 80
0:	lodsb
	and	al, 7
	xor	ah, ah
	mov	ax, [sched_graph_symbols + eax * 2]
	stosw
	loop	0b
	PRINT_END
	POP_SCREENPOS
	pop	edi
	pop	esi
	pop	ecx
	ret
.endif



# This method is typically called in an ISR.
# in: cs
# in: eax = task code offset
# in: ecx = size of argument
# in: esi = label for task
# out: eax = argument buffer
schedule_task:
	cmp	dword ptr [schedule_sem], -1
	jz	8f
	push	ebp	# alloc var ptr
	push	ebx
	push	ecx
	mov	ebp, esp # init var ptr: [+0]=arg ecx
	push	edx
	mov	ebx, eax

######## spin lock
	mov	ecx, 0x1000
0:	mov	eax, 2	# for future debugging - who has lock.
	xchg	[schedule_sem], eax
	or	eax, eax
	jz	0f
	SCHED_UPDATE_GRAPH 4
	DEBUG_DWORD eax
#	pause
pushf
sti
hlt
popf
	loop	0b
	printlnc 4, "failed to acquire schedule semaphore"
	DEBUG_DWORD eax
	stc
	jmp	9f
########
0:	ARRAY_LOOP [scheduled_tasks], SCHEDULE_STRUCT_SIZE, eax, edx, 9f
	cmp	dword ptr [eax + edx], -1
	jz	1f
	ARRAY_ENDL
9:	ARRAY_NEWENTRY [scheduled_tasks], SCHEDULE_STRUCT_SIZE, 4, 9f
1:	mov	[eax + edx + task_addr], ebx
	mov	[eax + edx + task_label], esi
########
	push	eax
	mov	eax, [ebp]
	or	eax, eax
	jz	2f
	call	malloc
2:	mov	ecx, eax
	pop	eax
	jnc	1f
	# no mem - unschedule task
	mov	dword ptr [eax + edx], -1
	jmp	9f
########
1:	mov	[eax + edx + task_arg], ecx
	mov	eax, ecx

	mov	dword ptr [schedule_sem], 0

9:	pop	edx
	pop	ecx
	pop	ebx
	pop	ebp
	ret

8:	DEBUG "scheduling disabled: caller="
	push	edx
	mov	edx, [esp + 4]
	call	printhex8
	pop 	edx
	call	newline
	ret
