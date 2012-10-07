.intel_syntax noprefix

SCHEDULE_DEBUG = 1

.struct 0
task_addr:	.long 0	# eip of task
task_arg:	.long 0	# value to be passed in edx
task_label:	.long 0	# name of task (for debugging)
task_registrar:	.long 0	# address from which schedule_task was called (for debugging when task_addr=0)
.data SECTION_DATA_BSS
schedule_sem: .long 0
scheduled_tasks: .long 0
SCHEDULE_STRUCT_SIZE = 12
argbuf: .space 256
.text32


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

	#push	ebx
	#mov	ax, [sched_graph_symbols + eax * 2]
	#call	printcharc
	#pop	ebx

	call	sched_update_graph
	pop	eax
.endif
.endm

.if SCHEDULE_DEBUG
.data SECTION_DATA_BSS
sched_graph: .space 80	# scoller
.data
sched_graph_symbols:
	.byte ' ', 0
	.byte '-', 0x4f
	.byte '-', 0x3f
	.byte '+', 0x2f
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
	and	al, 3
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


# This method is called immediately after an interrupt has handled,
# and it is the tail part of the irq_proxy.
schedule:
	cmp	dword ptr [scheduled_tasks], 0
	jz	1f
	# one-shot first-in-list
	push	eax
.if 1
	mov	eax, 1
	xchg	[schedule_sem], eax	# exactly 50% fault rate
	or	eax, eax
	jz	2f
.else
	push	ebx
	# if [schedule_sem] == eax 	# ZF
	# then [schedule_sem] = ebx	# ZF = 1
	# else eax = [schedule_sem]	# ZF = 0
	xor	eax, eax
	mov	ebx, 1
	lock cmpxchg	[schedule_sem], ebx	# 100% success rate
	pop	ebx
	#jnz	9f 	# sem was 1, task running, abort execution - timer will pick it up
	jz	2f
.endif
SCHED_UPDATE_GRAPH 1
	pop eax
	iret

	2:
	push	ebx
	push	ecx
	push	edx
	push	esi
########
	mov	ebx, [scheduled_tasks]
	xor	ecx, ecx	# index
########
0:	mov	eax, -1
	xchg	eax, [ebx + ecx + task_addr]
	mov	esi, [ebx + ecx + task_label]	# label
	mov	edx, [ebx + ecx + task_arg]	# ptr
	cmp	eax, -1
	jnz	0f
	or	eax, eax	# nullpointer check
	jz	4f
########
	add	ecx, SCHEDULE_STRUCT_SIZE
	cmp	ecx, [ebx + array_index]
	jb	0b
SCHED_UPDATE_GRAPH 2
	jmp	3f	# no task
0:
SCHED_UPDATE_GRAPH 3
########
.if SCHEDULE_DEBUG > 1
printc 0xf4, "[SCHEDULE "
pushcolor 0xf3
call print
popcolor
printc 0xf4, "]"
.endif
	# keep interrupt flag as before IRQ
#	test	word ptr [esp + 8 + 4 + 4], 1 << 9	# irq flag; 8:cs:eip, 4:eax, 4:edx
#	jz	2f
	sti
#2:
	pushad
	call	eax	# assume the task does not change segment registers
	popad
	.if 0
	mov	eax, edx
	call	mfree
	.endif

3:
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx

	mov	dword ptr [schedule_sem], 0	# free sem
9:	pop	eax
1:	iret

4:	printc 0xf4, "[schedule:null task: label='"
	call	print
	printc 0xf4, "' arg="
	call	printhex8
	printc 0xf4, " registrar="
	mov	edx, [ebx + ecx + task_registrar]
	call	printhex8
	printc 0xf4, "]"
	jmp	3b


# in: cs
# in: eax = offset
# in: ecx = size of argument
# out: eax = argument buffer
schedule_task:
	push	ebx
	push	ecx
	push	edx
	mov	ebx, eax

	ARRAY_LOOP [scheduled_tasks], SCHEDULE_STRUCT_SIZE, eax, edx, 9f
	cmp	dword ptr [eax + edx], -1
	jz	1f
	ARRAY_ENDL
9:	ARRAY_NEWENTRY [scheduled_tasks], SCHEDULE_STRUCT_SIZE, 4, 9f
1:	mov	[eax + edx], ebx
	mov	[eax + edx + 8], esi
.if 0
	push	eax
	mov	eax, ecx
	call	malloc	# TODO: more efficient buffer
	mov	ecx, eax
	pop	eax

	mov	[eax + edx + 4], ecx
	mov	eax, ecx
.else
mov eax, offset argbuf
.endif

	pop	edx
	pop	ecx
	pop	ebx
	ret

