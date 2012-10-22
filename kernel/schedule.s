#############################################################################
# Scheduler and Task Switching
#
# The task-switching implemented here replaces cs,ds,es,fs,gs,eflags,
# esp, and the general purpose registers. Note that only ss is not replaced.
#
# The scheduler distinguishes between two kinds of tasks: legacy, or
# job tasks, which are unmanaged threads executing on whatever stack
# was active when the scheduler is invoked,
# and 'context-switch' tasks, which are implemented by scheduling a
# continuation (i.e., schedule the call-stack, discard it, and iret to
# the context-switch task). The context-switch tasks have their own
# stack allocated automatically upon schedule (unlike continuations).
#
# In this manner, no process/task management is required, and no pid's
# are allocated, as ANY executing 'thread' can be interrupted and
# scheduled. Therefore, only postponed 'threads' are managed in the
# task schedule queue.

.intel_syntax noprefix

SCHEDULE_DEBUG = 1

SCHED_ROUND_ROBIN = 1
SCHED_MALLOC = 0	# 1: malloc/free schedule_task.ecx,eax; 0: use task_regs for storage.
TASK_SWITCH = 1	# experimental; set to 0 for legacy.

TASK_SWITCH_DEBUG = 0

.struct 0
task_reg_gs:	.long 0
task_reg_fs:	.long 0
task_reg_es:	.long 0
task_reg_ds:	.long 0
task_reg_ss:	.long 0
task_reg_edi:	.long 0
task_reg_esi:	.long 0
task_reg_ebp:	.long 0
task_reg_esp:	.long 0
task_reg_ebx:	.long 0
task_reg_edx:	.long 0
task_reg_ecx:	.long 0
task_reg_eax:	.long 0
task_reg_eip:	.long 0
task_reg_cs:	.long 0
task_reg_eflags:.long 0
TASK_REG_SIZE = .
.struct 0
.if SCHED_MALLOC
task_addr:	.long 0	# eip of task
task_arg:	.long 0	# value to be passed in edx
.endif
task_label:	.long 0	# name of task (for debugging)
task_registrar:	.long 0	# address from which schedule_task was called (for debugging when task_addr=0)
task_flags:	.long 0
task_stackbuf:	.long 0	# remembered for mfree
task_regs:	.space TASK_REG_SIZE
SCHEDULE_STRUCT_SIZE = .
.if SCHED_MALLOC
.else
.struct task_regs + task_reg_eip
task_addr: 
.struct task_regs
task_arg:
.endif
.data
schedule_sem:	.long -1 # -1: scheduling disabled; locked by: 1=schedule 2=schedule_task
.data SECTION_DATA_BSS
current_task:	.space SCHEDULE_STRUCT_SIZE
screen_pos_bkp: .long 0
scheduled_tasks: .long 0
schedule_delay: .long 0
.text32

# A fail-fast semaphore lock.
#
# This macro does a single check, leaving the semaphore in a locked state
# regardless of whether the lock succeeded.
# When the lock does not succeed, control is transferred to \nolocklabel.
# out: ZF = 1: have lock
# out: eax = 0 (have locK), other value: no lock.
.macro MUTEX_LOCK sem, nolocklabel=0
	.if 0 # INTEL_ARCHITECTURE > 3	# 486+ - TODO: check
	push	ebx
	mov	ebx, 1
	xor	eax, eax
	lock	cmpxchg \sem, ebx
	pop	ebx
	.else
	mov	eax, 1
	xchg	\sem, eax
	or	eax, eax
	.endif
	.ifnc 0,\nolocklabel
	jnz	\nolocklabel	# task list locked - abort.
	.endif
.endm


# This is a semi-spinlock, as it does not use CPU time when it fails 
# to acquire a lock. A lock is typically not going to become free unless
# an interrupt occurs (unless perhaps on SMP systems).
# Therefore, when lock acquisition fails, interrupts are enabled and
# the cpu is halted.
# Since the timer interrupt is essential for scheduling,
# and since this is the only way the scheduler is called, 
# and since on a single-CPU system the scheduler is the only 'process'
# that can obtain a lock,
# halting is the most efficient way to wait for a semaphore to become free.
#
# On an SMP system, potentially [pit_timer_interval] milliseconds are wasted,
# in the case where IRQ's are only executed by one CPU at a time,
# and where two or more CPU's are competing to register a task, where one
# has obtained a lock, and the other enters halt.
# I have not researched SMP systems, thus, it is possible that even though
# any IRQ is only executed on a single CPU at a time, that two different IRQ's,
# such as the timer and the network, are executed simultaneously. In this case,
# since all IRQ's (except exceptions), are mapped to the scheduler, it is
# possible that the scheduler is called concurrently. However, the 'fail-fast'
# lock mechanism would take care of attempting any task switch.
#
# out: CF = ZF (1: no lock; 0: lock)
# destroys: eax, ecx
.macro MUTEX_SPINLOCK sem, locklabel=0, nolocklabel=0
	.ifc 0,\locklabel
	_LOCKLABEL = 109f
	.else
	_LOCKLABEL = \locklabel
	.endif

	mov	ecx, 0x1000
100:
	.if INTEL_ARCHITECTURE > 3
		push	ebx
		mov	ebx, 1
		xor	eax, eax
		lock	cmpxchg \sem, ebx
		pop	ebx
		jz	109f
	.else
		xchg	\sem, eax
		or	eax, eax
		jz	109f
	.endif
	.if 1
	pushf
	sti
	hlt
	popf
	.else
	pause
	.endif
	loop	100b

	.ifc 0,\nolocklabel
		or	eax, eax
		stc
	.else
		jmp \nolocklabel
	.endif
109:	
.endm

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


debug_tasks:
	mov eax, [screen_pos]
	mov [screen_pos_bkp], eax
	mov dword ptr [screen_pos], 160*3
	mov ecx, 80 * 16
	mov edi, 160 * 2
	push es
	mov eax, SEL_vid_txt
	mov es, ax
	mov ax, 0x1000
	rep stosw
	pop es

	pushfd
	pop edx
	DEBUG_DWORD edx, "FLAGS"
	DEBUG_DWORD [ebp+task_reg_eflags]
	call printspace

	call	cmd_tasks		
	mov	eax, [screen_pos_bkp]
	mov	[screen_pos], eax
	ret


#############################################################################
# This method is called immediately after an interrupt has handled,
# and it is the tail part of the irq_proxy.
.if TASK_SWITCH
.data SECTION_DATA_BSS
block_schedule: .long 0
b_cnt: .long 0
recur: .long 0
.text32
schedule:
	.if 1#TASK_SWITCH_DEBUG
		inc	dword ptr [schedule_delay]
		cmp	dword ptr [schedule_delay], 1#50
		jae	1f
		iret
		1:
		mov dword ptr [schedule_delay], 0
	.endif
pushad
push ss
push ds
push es
push fs
push gs
mov ebp, esp
mov eax, SEL_compatDS
mov ds, eax

PUSH_SCREENPOS
MUTEX_LOCK [block_schedule]
#jnz	999f
or eax, eax
jz 1f
	mov [screen_pos], dword ptr 160
	printcharc 0xc0, 'x'

	inc dword ptr [b_cnt]
	mov edx, [block_schedule]
	call printhex8
	DEBUG_DWORD eax
	call printspace
	mov edx, [b_cnt]
	call printhex8
	call printspace
	mov edx, [ebp + task_reg_eflags]
	call printhex8
	call printspace
	mov edx, [ebp + task_reg_eip]
	call printhex8
	pushad
	call debug_tasks
	popad

	stc
	jmp 2f
1:
	mov [screen_pos], dword ptr 160
	printcharc 0xa0, 'v'
	mov edx, [ebp + task_reg_eflags]
	call printhex8
	call printspace
	mov edx, [ebp + task_reg_eip]
	call printhex8
	clc
2:
POP_SCREENPOS
pop gs
pop gs
pop es
pop ds
pop ss
popad
jc 999f

	# preserve all registers for task switch. eip:cs:eflags already on stack.
	pushad	# eax, ecx, edx, ebx, esp, ebp, esi, edi
	push	ss
	push	ds
	push	es
	push	fs
	push	gs
	mov	ebp, esp	# ebp + 4*(4+8) = eip:cs:flags/eip

	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax

	.if 1 # TASK_SWITCH_DEBUG
		call debug_tasks
	.endif

	.if TASK_SWITCH_DEBUG > 1
		DEBUG "sched ret"
		DEBUG_DWORD esp
		DEBUG_DWORD [ebp+task_reg_cs],"cs"
		DEBUG_DWORD [ebp+task_reg_eip],"eip"
		DEBUG_DWORD [ebp+task_reg_esp],"esp"
		call newline
	.endif

	# TODO: lock task queue
	# task queue is locked/unloacked in get_scheduled_task
	call	get_scheduled_task$	# out: eax, edx, ebx
	jc 9f	#no task, return to current task

# in: edx = task args (task_regs)
# in: ebx = task flags
	.if TASK_SWITCH_DEBUG
		printchar 'T'
		DEBUGS [edx-task_regs+task_label]

		.if TASK_SWITCH_DEBUG > 1 # SCHEDULE_DEBUG==2
			DEBUG "!!!!!!!!!!!!!!!";DEBUG_DWORD ebx
			push	eax
			mov	al, 'a'
			test	ebx, 1
			jz	1f
			mov	al, 'b'
		1:	call	printchar
			pop	eax
		.endif
	.endif

	test	ebx, 2	# whether this task requires context switch
	jz	1f	# nope, legacy task (job)

	# impending context switch - schedule continuation:
	#printchar 'C'
	#MUTEX_LOCK [schedule_sem], 9f	# abort

	sub edx, [scheduled_tasks]
	pushad
	mov	eax, offset task_switch_continuation #debug label
	mov	ecx, TASK_REG_SIZE
	mov	ebx, 2
	LOAD_TXT "continuation"
	call	schedule_task_LEGACY	# out: eax = task arg buf
	jc	2f
	mov	ecx, TASK_REG_SIZE
	mov	edi, eax
	mov	esi, ebp
	rep	movsb
	# update esp, as it's value points to eip;cs:eflags
	add	[eax + task_reg_esp], dword ptr 12
	clc
	2:popad
	jnc	2f
	printc 12, "FAIL SCHED CONT"	
	jmp 9f
	2:
	add edx, [scheduled_tasks]
	# TODO: unlock

	# context switch.
	.if SCHEDULE_IRET
		# ignore current stack: task is continuation.
	#	cmp	[edx - task_regs + task_stackbuf], dword ptr 0
	#	jz 3f
		mov	edi, [edx + task_reg_esp]
	#	or	edi, edi
	#	jnz	2f
	#	# use current stack
	#3:	mov	edi, esp
	2:	sub	edi, TASK_REG_SIZE
		mov	esp, edi
		mov	esi, edx
		mov	ecx, TASK_REG_SIZE
		rep	movsb

		# data copied, mark task spot as available:
		mov	[edx - task_regs + task_flags], dword ptr -1

		mov eax, edx
		mov ecx, [scheduled_tasks]
		sub eax, ecx
		sub eax, offset task_regs
		# eax is now index to task
		# check whether task is last, if so, decrease array_index
		add eax, SCHEDULE_STRUCT_SIZE
		# if eax was last index, it should now equal array_index:
		cmp	eax, [ecx + array_index]
		jnz 2f
		# XXX NOT LOCKED
		sub dword ptr [ecx + array_index], SCHEDULE_STRUCT_SIZE
		2:



			mov	edi, offset current_task
			lea	esi, [edx - task_regs]
			mov	ecx, SCHEDULE_STRUCT_SIZE
			rep	movsb

mov	dword ptr [block_schedule], 0
		pop	gs
		pop	fs
		pop	es
		pop	ds
		add	esp, 4	# pop sp
		popad
		or	word ptr [esp + 8], 1<<9	# enable int

		.if TASK_SWITCH_DEBUG
			push ebp
			lea ebp, [esp + 4]
			DEBUG "r1"
			DEBUG_DWORD ebp
			DEBUG_DWORD [ebp+4],"cs"
			DEBUG_DWORD [ebp+0],"eip"
			DEBUG_DWORD [ebp+8],"eflags"
			printchar '*'
			mov ebp, [screen_pos_bkp]
			mov [screen_pos], ebp
			pop ebp

		.endif
		#DEBUG "HALT"; 0:hlt;jmp 0b
		iret
		sched_context_switch$:	# debug symbol

	.else
	.error "TASK_SWITCH requires SCHEDULE_IRET"
	.endif #SCHEDULE_IRET


1:	# task requires no context switch - treat it like a job
	call	call_task

		.if SCHED_MALLOC
		or	eax, eax
		jz	2f
		mov	eax, edx
		call	mfree
	2:
		.endif


		mov	edi, offset current_task
		mov	eax, [esp + task_reg_eip]
		mov	[edi + task_addr], eax
		mov	eax, [esp + task_reg_esp]
		mov	[edi + task_regs+task_reg_esp], eax
		LOAD_TXT "<default>"
		mov	[edi + task_label], esi



9:	
	.if TASK_SWITCH_DEBUG
		mov ebx, [screen_pos_bkp]
		mov [screen_pos_bkp], ebx
	.endif

mov	dword ptr [block_schedule], 0
	pop	gs
	pop	fs
	pop	es
	pop	ds
	add	esp, 4	# pop	ss
	popad
999:
.if SCHEDULE_IRET
	iret
.else
	ret
.endif


.else

schedule: # _LEGACY:
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

	# TODO: lock task queue (it is locked/released in get_scheduled_task$)
	call	get_scheduled_task$	# out: eax, edx, ebx
	jc	9f
	# keep interrupt flag as before IRQ
	# access EFLAGS: ebp + 4 -> eip:cs:eflags (+12 then ->eflags)
	# unless SCHEDULE_IRET = 0: a return ptr then preceeds eip on stack.
	test	word ptr [ebp + 4*(12+SCHEDULE_IRET-1)], 1 << 9 # irq flag;
	jz	1f
	sti
1:
	call	call_task

	.if SCHED_MALLOC
	or	edx, edx
	jz	9f
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

.endif

# in: eax = task addr
# in: edx = task arg (task_regs)
call_task:
	pushad		# assume the task does not change segment registers

		mov	edi, offset current_task
		lea	esi, [edx - task_regs]
		mov	ecx, SCHEDULE_STRUCT_SIZE
		rep	movsb

	push	eax
	.if SCHEDULE_DEBUG > 1
		DEBUG_DWORD eax, "call task"
		DEBUGS [edx + -task_regs + task_label]
		DEBUG "S"
		DEBUG_DWORD [edx + task_reg_ebx], "ebx"
		DEBUG_DWORD [edx + task_reg_esi], "esi"
	.endif
	#pushad	# eax, ecx, edx, ebx, esp, ebp, esi, edi
	push	dword ptr [edx + task_reg_eax]
	push	dword ptr [edx + task_reg_ecx]
	push	dword ptr [edx + task_reg_edx]
	push	dword ptr [edx + task_reg_ebx]
	push	dword ptr [edx + task_reg_esp] # ignored
	push	dword ptr [edx + task_reg_ebp]
	push	dword ptr [edx + task_reg_esi]
	push	dword ptr [edx + task_reg_edi]
	#TODO: release task queue
		# mark as free
		mov	[edx - task_regs + task_flags], dword ptr -1
	# as this is legacy, the task runs on whatever stack, as it returns.
	popad
mov	dword ptr [block_schedule], 0
	sti
	call	[esp]
	pop	eax

	popad
	ret

#############################################################################

.if 1# TASK_SWITCH
# just for label
task_switch_continuation:
	ret

task_switch_debug_task:
	pushf
	cli
	PUSH_SCREENPOS
	pushcolor 0xf0
	mov	[screen_pos], dword ptr 160
	push	edx
	print	"clock "
	mov	edx, [clock]
	call	printhex8
	print	" recursion "
	mov	edx, [recur]
	call	printdec32
	print	" esp "
	mov	edx, esp
	call	printhex8
.if SCHED_ROUND_ROBIN
	print	" task index "
	mov	edx, [task_index]
	call	printhex4
	printchar '/'
.endif
	push	eax
	push	ebx
	mov	eax, [scheduled_tasks]
	mov	eax, [eax + array_index]
	xor 	edx, edx
	mov	ebx, SCHEDULE_STRUCT_SIZE
	div	ebx
	mov	edx, eax
	call	printdec32
	pop	ebx
	pop	eax
	pop	edx
	popcolor
	POP_SCREENPOS
	#PRINTCHAR '$'
	popf
	ret
.endif

.if SCHED_ROUND_ROBIN
.data SECTION_DATA_BSS
task_index: .long 0
.text32
.endif

# locks scheduled_tasks, finds and removes a task from the queue,
# and returns a pointer to the task information, leaving the semaphore locked.
# On return, CF indicates failure/success. When CF is set, either the lock
# could not obtained, or there are no scheduled tasks. When there are no
# scheduled tasks, the lock is released.
# When CF is 0, eax contains the task pointer, and the lock is left intact,
# so that the caller has 'time' to use the data without any risk of it being
# overwritten. Typical use is to release this lock as soon as possible,
# and thus the caller should copy the data on the appropriate stack and
# then release the lock before calling the task.
#
# out: eax = task ptr
# out: edx = task arg
# out: ebx = task flags (if TASK_SWITCH)
# out: esi = task label
# out: CF = 1: no task or cannot lock task list
get_scheduled_task$:
	# schedule_task does spinlock, so we don't, as this
	# method is called regularly.
	MUTEX_LOCK [schedule_sem], 9f
	push	ecx
########
	# one-shot first-in-list
	mov	ebx, [scheduled_tasks]
	or	ebx, ebx
	jz	1f
.if SCHED_ROUND_ROBIN
	mov	ecx, [task_index]
	# increment task index for round robin
	mov	eax, ecx
	sub	eax, SCHEDULE_STRUCT_SIZE
	#cmp	eax, [ebx + array_index]
	jns	2f
	#xor	eax, eax
	mov	eax, [ebx + array_index]
	sub	eax, SCHEDULE_STRUCT_SIZE
2:	mov	[task_index], eax
.else
	xor	ecx, ecx	# index
.endif
########
0:
	mov	eax, [ebx + ecx + task_addr]
.if SCHED_MALLOC
	mov	edx, [ebx + ecx + task_arg]	# ptr
.else
	lea	edx, [ebx + ecx + task_arg]	# NOTE! requires lock!
.endif
	cmp	[ebx + ecx + task_flags], dword ptr -1
	jnz	0f
########
	
	add	ecx, SCHEDULE_STRUCT_SIZE
.if SCHED_ROUND_ROBIN
	cmp	ecx, [task_index]
	jz	1f
.endif
	cmp	ecx, [ebx + array_index]
	jb	0b
.if SCHED_ROUND_ROBIN
	xor	ecx, ecx
	cmp	ecx, [task_index]
	jnz	0b
.endif
########
1:	SCHED_UPDATE_GRAPH 2
	stc
	jmp	1f	# no task
0:	## null check
	or	eax, eax
	jnz	2f
	printc 4, "ERROR: scheduled task address NULL: registrar: "
	push	edx
	mov	edx, [ebx + ecx + task_registrar]
	call	printhex8
	call	newline
	pop	edx
	mov	[ebx + ecx + task_addr], dword ptr -1
	mov	[ebx + ecx + task_flags], dword ptr -1
	.if SCHED_MALLOC
	or	eax, eax
	jz	3f
	mov	eax, edx
	call	mfree
	3:
	.endif
	SCHED_UPDATE_GRAPH 5
	stc
	jmp	1f
2:	##
	SCHED_UPDATE_GRAPH 3
	clc

########
	add	ecx, ebx
	#mov	ebx, -1	# mark as free
	#xchg	ebx, [ecx + task_flags]
	mov	ebx, [ecx + task_flags]
	# mark as 'pending'; continuatoin may be scheduled,
	# using the src stack, so the data cannot be copied yet
	# over that stack before scheduling continuation.
	# scheduling continuatio nhwoever can also not overwrite
	# this task yet.
	# Set to -1 once data is copied.
	or	dword ptr [ecx + task_flags], 0x88880000

	.if TASK_SWITCH_DEBUG > 1
		DEBUG "TASK:"
		DEBUG_DWORD [edx -task_regs + task_flags]
		DEBUG_DWORD [edx -task_regs + task_addr]
		DEBUG_DWORD [edx + task_reg_esp]
		DEBUG_DWORD ebx, "flags"
	.endif
	clc
1:	pop	ecx
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
	.byte 'x', 0xf4	# 5: fail to schedule
	.byte 'A', 0x0f
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

# in: edx = address of mutex/semaphore
# in: eax = id - value to put in semaphore (debugging: who has lock)
# out: CF
spinlock:
	push	ecx
	mov	ecx, 0x1000	# timeout
0:	xchg	[edx], eax
	or	eax, eax
	jz	0f	# lock was 0
	SCHED_UPDATE_GRAPH 4; DEBUG_DWORD eax
	.if 0
		pause
	.else
		pushf
		sti
		hlt
		popf
	.endif
	loop	0b
	printc 4, "failed to acquire schedule semaphore"
	DEBUG_DWORD eax
	call	newline
	stc
0:	pop	ecx
	ret

# NOTE! This method does not lock, so be sure to lock/unlock!
#
# in: cs
# in: eax = offset
# in: ebx = flags
# in: ecx = arg len
schedule_task_internal:
	cmp	dword ptr [schedule_sem], -1
	jz	8f
	push	ebp	# alloc var ptr
	push	eax
	push	ebx
	push	ecx
	mov	ebp, esp # init var ptr: [+0]=arg ecx, [+4]=arg ebx
	push	edx

########
0:
	mov	ebx, [ebp + 8] # original eax
	# check whether task is already scheduled
	ARRAY_LOOP [scheduled_tasks], SCHEDULE_STRUCT_SIZE, eax, edx, 2f
	cmp	[eax + edx + task_flags], dword ptr -1
	jz	1f
	cmp	[eax + edx + task_addr], ebx
	jnz	1f
	.if SCHEDULE_DEBUG > 1
		DEBUG "<< DUP LEGACY TASK:"
		DEBUGS [eax + edx + task_label]
		DEBUG ">>"
	.endif
	stc
	jmp	7f
	1:
	ARRAY_ENDL

	# find empty slot
	ARRAY_LOOP [scheduled_tasks], SCHEDULE_STRUCT_SIZE, eax, edx, 2f
	cmp	dword ptr [eax + edx + task_flags], -1
	jz	1f
	ARRAY_ENDL
2:	ARRAY_NEWENTRY [scheduled_tasks], SCHEDULE_STRUCT_SIZE, 10, 7f
1:	
	.if TASK_SWITCH_DEBUG > 1
		DEBUG_DWORD edx "task idx"
		DEBUGS esi
	.endif
	push	edi
	lea	edi, [eax + edx]
	mov	ecx, SCHEDULE_STRUCT_SIZE
	push	eax
	xor	eax, eax
	rep	stosb
	pop	eax
	pop	edi

	mov	[eax + edx + task_addr], ebx
	mov	[eax + edx + task_label], esi
	push	dword ptr [ebp + 4]
	pop	dword ptr [eax + edx + task_flags]
	push	dword ptr [ebp + 12]
	pop	dword ptr [eax + edx + task_registrar]
	.if TASK_SWITCH_DEBUG > 1
		SCHED_UPDATE_GRAPH 6 # 'A'
	.endif
########
	.if SCHED_MALLOC
		push	eax
		mov	eax, [ebp]
		or	eax, eax
		jz	1f
		call	malloc
	1:	mov	ecx, eax
		pop	eax
		jnc	1f
		# no mem - unschedule task
		mov	dword ptr [eax + edx], -1
		jmp	8f
	########
	1:
	.else
		lea	ecx, [eax + edx + task_regs]
	.endif
	mov	[eax + edx + task_arg], ecx
	mov	eax, ecx

7:

9:	pop	edx
	pop	ecx
	pop	ebx
	add	esp, 4	# pop eax
	pop	ebp
	ret

8:	DEBUG "scheduling disabled: caller="
	push	edx
	mov	edx, [esp + 4]
	call	printhex8
	pop 	edx
	call	newline
	ret



# This method is typically called in an ISR.
# Calling convention: stdcall:
#	PUSH_TXT "task name"
#	push	dword ptr 0|1	# flags
#	push	cs
#	.if [realsegflat] != 0
#		.if eax is arg to task
#		push	eax
#		mov	eax, offset task
#		add	eax, [realsegflat]
#		xchg	eax, [esp]
#		.else
#		mov	eax, offset task
#		add	eax, [realsegflat]
#		push	eax
#		.endif
#	.else
#	push	dword ptr offset task
#	.endif
# in: [esp + 4]: eip - address of task
# in: [esp + 8]: cs - code seg of task
# in: [esp + 12]: task flags: bit 1: 0=call/job/handler; 1=context switch
# in: [esp + 16]: label for task
# in: all registers are preserved and offered to the task.
# calling convention: stdcall [rtl, callee (this method) cleans stack]
schedule_task:
	cmp	dword ptr [schedule_sem], -1
	jz	8f
	# copy regs to stack
	pushad
	push	ss
	push	ds
	push	es
	push	fs
	push	gs
	mov	ebp, esp

######## spin lock
	MUTEX_SPINLOCK [schedule_sem], nolocklabel=9f
########
	mov	ebx, [ebp + TASK_REG_SIZE - 12 + 4]	# eip
	# check whether task is already scheduled
	ARRAY_LOOP [scheduled_tasks], SCHEDULE_STRUCT_SIZE, eax, edx, 2f
	cmp	[eax + edx + task_flags], dword ptr -1
	jz	1f
	cmp	[eax + edx + task_addr], ebx
	jnz 1f
	.if TASK_SWITCH_DEBUG
		DEBUG "<<< DUP TASK >>>"
	.endif
	stc
	jmp	7f
	1:
	ARRAY_ENDL

	# find empty slot
	ARRAY_LOOP [scheduled_tasks], SCHEDULE_STRUCT_SIZE, eax, edx, 2f
	cmp	dword ptr [eax + edx + task_flags], -1
	jz	1f
	ARRAY_ENDL
2:	ARRAY_NEWENTRY [scheduled_tasks], SCHEDULE_STRUCT_SIZE, 4, 7f
1:	mov	ebx, eax	# using lodsd
	lea	edi, [ebx + edx + task_regs]
	mov	esi, ebp
	mov	ecx, TASK_REG_SIZE - 12	# eip, cs, eflags not copied
	rep	movsb
	add	esi, 4	# skip method return
	movsd	# eip
	movsd	# cs
	pushfd	# need some eflags
	pop	eax
	or	eax, 1 << 9	# sti
	mov	dword ptr [ebx + edx + task_regs + task_reg_eflags], eax
	# we need a stack...
	mov	[edi - TASK_REG_SIZE + task_reg_esp], dword ptr 0 # zero stack: alloc

	lodsd	# task flags
	mov	[ebx + edx + task_flags], eax
	lodsd	# task tabel
	mov	[ebx + edx + task_label], eax
	push	dword ptr [ebp + task_reg_eip]
	pop	dword ptr [ebx + edx + task_registrar]

	#
	test	dword ptr [ebx + edx + task_flags], 2
	jz	7f
	# allocate a stack
	mov	eax, 1024
	call	malloc
	jc	7f
	mov	[ebx + edx + task_stackbuf], eax
	add	eax, 15
	and	eax, ~0xf
	mov	[ebx + edx + task_regs + task_reg_esp], eax
########
7:	mov	dword ptr [schedule_sem], 0

9:	pop	gs
	pop	fs
	pop	es
	pop	ds
	add	esp, 4	#pop	ss
	popad
	ret	16

#10:	SCHED_UPDATE_GRAPH 4; DEBUG_DWORD eax
#	jmp	9b

8:	DEBUG "scheduling disabled: caller="
	push	edx
	mov	edx, [esp + 4]
	call	printhex8
	pop 	edx
	call	newline
	ret	16




# in: cs
# in: eax = offset
# in: ebx = flags
# in: ecx = arg len
schedule_task_LEGACY:
	cmp	dword ptr [schedule_sem], -1
	jz	8f
	push	ebp	# alloc var ptr
	push	eax
	push	ebx
	push	ecx
	mov	ebp, esp # init var ptr: [+0]=arg ecx, [+4]=arg ebx
	push	edx

######## spin lock
	MUTEX_SPINLOCK [schedule_sem], nolocklabel=9f
########
0:
	mov	ebx, [ebp + 8] # original eax
	# check whether task is already scheduled
	ARRAY_LOOP [scheduled_tasks], SCHEDULE_STRUCT_SIZE, eax, edx, 2f
	cmp	[eax + edx + task_flags], dword ptr -1
	jz	1f
	cmp	[eax + edx + task_addr], ebx
	jnz	1f
	.if SCHEDULE_DEBUG > 1
		DEBUG "<< DUP LEGACY TASK:"
		DEBUGS [eax + edx + task_label]
		DEBUG ">>"
	.endif
	stc
	jmp	7f
	1:
	ARRAY_ENDL

	# find empty slot
	ARRAY_LOOP [scheduled_tasks], SCHEDULE_STRUCT_SIZE, eax, edx, 2f
	cmp	dword ptr [eax + edx + task_flags], -1
	jz	1f
	ARRAY_ENDL
2:	ARRAY_NEWENTRY [scheduled_tasks], SCHEDULE_STRUCT_SIZE, 4, 7f
1:	
	.if TASK_SWITCH_DEBUG > 1
		DEBUG_DWORD edx "task idx"
		DEBUGS esi
	.endif
	push	edi
	lea	edi, [eax + edx]
	mov	ecx, SCHEDULE_STRUCT_SIZE
	push	eax
	xor	eax, eax
	rep	stosb
	pop	eax
	pop	edi

	mov	[eax + edx + task_addr], ebx
	mov	[eax + edx + task_label], esi
	push	dword ptr [ebp + 4]
	pop	dword ptr [eax + edx + task_flags]
	push	dword ptr [ebp + 12]
	pop	dword ptr [eax + edx + task_registrar]
	.if TASK_SWITCH_DEBUG > 1
		SCHED_UPDATE_GRAPH 6 # 'A'
	.endif
########
	.if SCHED_MALLOC
		push	eax
		mov	eax, [ebp]
		or	eax, eax
		jz	1f
		call	malloc
	1:	mov	ecx, eax
		pop	eax
		jnc	1f
		# no mem - unschedule task
		mov	dword ptr [eax + edx], -1
		jmp	8f
	########
	1:
	.else
		lea	ecx, [eax + edx + task_regs]
	.endif
	mov	[eax + edx + task_arg], ecx
	mov	eax, ecx

7:	mov	dword ptr [schedule_sem], 0

9:	pop	edx
	pop	ecx
	pop	ebx
	add	esp, 4	# pop eax
	pop	ebp
	ret

8:	DEBUG "scheduling disabled: caller="
	push	edx
	mov	edx, [esp + 4]
	call	printhex8
	pop 	edx
	call	newline
	ret


#############################################################################

cmd_tasks:
	xor	ecx, ecx
	print "Tasks: "
	mov	edx, [scheduled_tasks]
	or	edx, edx
	jz	9f
.if SCHED_ROUND_ROBIN
	push	edx
	mov	edx, [task_index]
	call	printhex8
	pop	edx
	printchar_ '/'
.endif
	mov	edx, [edx + array_index]
	call	printhex8
	call	newline

	call	task_print_h$

	xor	ebx, ebx
	mov	eax, offset current_task
	printc 0x0f, "C "
	call	task_print$
	call	newline

	xor	ecx, ecx
	ARRAY_LOOP [scheduled_tasks], SCHEDULE_STRUCT_SIZE, eax, ebx, 9f
	pushcolor 7
	#	cmp	[eax + ebx + task_flags], dword ptr -1
	#	jz	3f

	mov	edx, ecx
	call	printdec32
	call	printspace

	mov	edx, [eax + ebx + task_addr]
	cmp	edx, [current_task + task_addr]
	jnz	1f
	color 15 # 0xf0
	jmp	2f

1:	cmp	[eax + ebx + task_flags], dword ptr -1
	jnz	2f
	color 8

2:	call	task_print$
3:	inc	ecx
	popcolor
	ARRAY_ENDL
9:	ret

task_print_h$:
	printlnc 11, "  addr.... stack... flags.... registr eflags.. label, symbol"
	ret

task_print$:
	mov	edx, [eax + ebx + task_addr]
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + task_regs + task_reg_esp]
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + task_flags]
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + task_registrar]
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + task_regs + task_reg_eflags]
	call printhex8
	call	printspace
#call newline
	mov	esi, [eax + ebx + task_label]
	call	print
	call	printspace
	mov	edx, [eax + ebx + task_addr]
#	call	debug_printsymbol
	call	debug_getsymbol
	jc	1f
	pushcolor 14
	call	println
	popcolor
	ret
1:	pushad
	call	debug_get_preceeding_symbol
	jc	1f
	pushcolor 13
	call	print
	print " + "
	sub	edx, eax
	call	printhex8
	popcolor
1:	call	newline
	popad

	ret
