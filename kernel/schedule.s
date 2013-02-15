#############################################################################
# Scheduler and Task Switching
#
# Scheduling: keeping track of future tasks.
#
# Scheduler: responsible for ordering and executing those tasks, aswell as
# scheduling future execution of the current task.
#
# The task-switching implemented here replaces cs,ds,es,fs,gs,ss,eflags,
# esp, the general purpose registers, and eip.
#
# The scheduler distinguishes between two kinds of tasks:
#
# legacy/jobs, which are unmanaged threads executing on whatever stack
# was active when the scheduler is invoked, and
#
# 'context-switch' tasks, which are implemented by scheduling a
# continuation (i.e., schedule the call-stack, discard it, and iret to
# the context-switch task). The context-switch tasks have their own
# stack allocated automatically upon schedule (unlike continuations).
#
# In this manner, no process/task management is required, and no pid's
# are allocated, as ANY executing 'thread' can be interrupted and
# scheduled. Therefore, only postponed 'threads' are managed in the
# task schedule queue.
#
# However, upon initialisation of the scheduler, an initial task is allocated,
# to store the continuation data. This data is not stored in the task
# entry, but in the stack it points to.
#
# Jobs however, are run from the scheduler, with the scheduler disabled,
# in kernel context. Jobs then are not meant to be interrupted.
# When the task within which the job is running is interrupted,
# its stackpointer gets to be updated to point to the job rather than
# the task where it was executing. However, since the job runs on that
# stack, when that task gets continued, the job running on it is activated.
# Once the job finishes, the task continues, as the stack would be the
# same as what it was when the task was interrupted and scheduled as
# a continuation, to run the job.
#
# In this implementation however, the task and job running within it are
# not expressly connected (except by an initial stack distance).
# Thus, it is possible, if scheduling were enabled when a job is run,
# that the original task gets continued, which will then destroy the
# job's stack. To prevent this, a job should be scheduled as a task
# with its own stack, which makes for only one kind of task.
#
# An alternative solution would be to remember the original stack top
# of the job, and whenever the job gets interrupted, to copy the stack
# to another context. The idea of a job is that initially all it requires
# is the kernel selectors, the general purpose registers, and a temporary
# local stack. This is then a portable (moveable) job, as it's stack
# requirements are known.
#
# Without having interruptable jobs, jobs such as the keyboard handler,
# which at current includes the screen history, will prevent other jobs
# and tasks from being continued, as the scheduler is disabled when a
# job is running.
#
# The network handler does send and receive packets in a job, and with
# scheduling disabled, cannot really wait for packets, since further
# packet handling for incoming packets can be scheduled but not executed.
#
# Jobs are meant to be quickly-run after some IRQ, to execute handling
# code without blocking interrupts. Interactive jobs require scheduling,
# and thus, for the scheduler to be enabled. This means that it's stack,
# and thus, all values on the stack above esp, need to be protected.
# In a flat address space comparing stack pointers will cause problems,
# thus, jobs need to link to their parent task, and set a flag to prevent
# the parent task from being scheduled as long as the job exists.
#
# Taking the approach of a possible job-stack within a task, a second
# array for jobs could be linked to a task, marking which stacks are occupied
# by child processes (jobs).
#
# For an interactive job such as a network service handler, which does I/O,
# the time between sending and receiving packets may be longer than it is
# desired that the task be suspended.
# Such a job may schedule it's own continuation; however, this needs to
# occur on a neutral stack. Thus, the job needs to return to it's caller.
# Generally speaking for network jobs, these are automatically created
# whenever there is inbound traffic. As suchs, jobs needs to follow a pure
# event-handling architecture. They manage their own state information
# such as tcp connection lists, which they can use to associate incoming
# packets to determine the next state in the protocol they implement.
# Thus, a job should never wait for an event, as it gets triggered by one.
#
# At current, the task that got interrupted to execute a job is left marked
# as running, and thus will not be scheduled (meaning, considered for
# execution). It then is safe to enable the scheduler for jobs, since
# only tasks that are not running jobs can be scheduled.
#
# Jobs can be enabled or disabled at compile-time. When disabled, all jobs
# are treated like tasks and receive a 1k stack.
.intel_syntax noprefix

SCHEDULE_DEBUG		= 0
SCHEDULE_DEBUG_MUTEX	= 0	# 1=print at cursor, 2=print at topleft
SCHEDULE_DEBUG_TOP	= 0	# 0..3; default value of env variable "sched.debug"
SCHEDULE_DEBUG_GRAPH	= 1	# ticker-tape

SCHEDULE_ROUND_ROBIN	= 1	# the default; has no effect when SCHED.._JOBS=0
SCHEDULE_JOBS		= 0	#buggy# 0 means jobs are treated like tasks
SCHEDULE_CLEAN_STACK	= 1	# zeroes the stack for each new job; ovrhd:264 clocks

JOB_STACK_SIZE		= 1024 * 4

TASK_SWITCH_INTERVAL	= 0	# nr of timer ticks between scheduling (debug)
TASK_SWITCH_DEBUG	= 0	# 0..4 very verbose printing of pivoting
TASK_SWITCH_DEBUG_JOB	= 0	# job completion (no effect when !SCHEDULE_JOBS)
TASK_SWITCH_DEBUG_TASK	= 0	# task completion

.struct 0	# stack order
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
.align 4	# for movsd (future modifications)
TASK_REG_SIZE = .
.struct 0	# scheduled task structure
task_pid:	.long 0
task_label:	.long 0	# name of task (for debugging)
task_registrar:	.long 0	# debugging: address from which schedule_task was called
task_flags:	.long 0	# bit 1: 1=task (ctx on task_task);0=job (task_regs)
	# task configuration flags:
	TASK_FLAG_TASK		= 0x0001
	TASK_FLAG_RESCHEDULE	= 0x0010	# upon completion, sched again
	# task wait flags:
	TASK_FLAG_WAIT_IO	= 0x0100	# task waiting for IO
	TASK_FLAG_WAIT_MUTEX	= 0x0200	# task waiting for MUTEX avail
	# task status flags:
	TASK_FLAG_RUNNING	= 0x8000 << 16	# do not schedule
	TASK_FLAG_SUSPENDED	= 0x4000 << 16
	TASK_FLAG_DONE		= 0x0100 << 16	# (aligned with RESCHEDULE)
	TASK_FLAG_CHILD_JOB	= 0x0010 << 16	# a job is using this stack

	TASK_FLAG_RING0		= 0x0000 << 16
	TASK_FLAG_RING1		= 0x0001 << 16
	TASK_FLAG_RING2		= 0x0002 << 16
	TASK_FLAG_RING3		= 0x0003 << 16
	TASK_FLAG_RING_MASK	= 0x0003 << 16
	TASK_FLAG_RING_SHIFT	= 16
task_parent:	.long 0
task_tls:	.long 0
task_stackbuf:	.long 0	# remembered for mfree
task_stack:
task_stack_esp:	.long 0	# 16 byte aligned
task_stack_ss:	.long 0
# these values are only used for jobs:
.align 4	# for movsd (future modifications)
task_regs:	.space TASK_REG_SIZE
SCHEDULE_STRUCT_SIZE = .
.data
task_queue_sem:	.long -1	# -1: scheduling disabled
scheduler_current_task_idx: .long -1
.data SECTION_DATA_BSS
pid_counter:	.long 0
task_queue:	.long 0
tls:		.long 0 # task/thread local storage (not SMP friendly perhaps?)
.tdata
tls_pid:	.long 0	# not used - no tls setup in this file.
tls_task_idx:	.long 0	# not used - no tls setup in this file.
.tdata_end
.text32

################################################################
# Debug: scheduler 'graph' (ticker-tape)
#

# nr: 3 = failed to acquire lock
# nr: 2 = lock success, executing task
# nr: 1 = lock success, no task
# nr: 0 = no data
.macro SCHED_UPDATE_GRAPH nr
.if SCHEDULE_DEBUG_GRAPH
	push	eax
	.ifc bl,\nr
	movzx	eax, \nr
	.else
	mov	eax, \nr
	.endif
	call	sched_update_graph
	pop	eax
.endif
.endm


# Various other debug macro's in order to keep source readable.

.macro DEBUG_PRINT_HLINE
.if TASK_SWITCH_DEBUG
	call	newline
	mov	ecx, 80
	mov	ax, 0xe000
990:	call	printcharc
	loop	990b
.endif
.endm



.macro DO_DEBUG_SCHEDULE_MUTEX
.if SCHEDULE_DEBUG_MUTEX
	pushf
	mov	eax, (0x0c<<8|'x')<<16 | (0x0a<<8|'v')

	.if SCHEDULE_DEBUG_MUTEX == 2	# print at topleft of screen
		PUSH_SCREENPOS 0
	.endif

	jnc	991f
	SCHED_UPGRADE_GRAPH 1
	shr	eax, 16
991:	call	printcharc

	.if SCHEDULE_DEBUG_MUTEX == 2
		DEBUG_DWORD [mutex]

		.data SECTION_DATA_BSS
		b_cnt$:.long 0	# how many times the SCHEDULE mutex failed
		.text32
		mov	edx, [b_cnt$]
		inc	dword ptr [b_cnt$]
		call	printhex8

		POP_SCREENPOS
	.endif
	popf
.endif
.endm


.macro DO_SCHEDULER_DEBUG_PIVOT
.if TASK_SWITCH_DEBUG > 2
	push	ebp
	lea	ebp, [esp + 4]
	mov	ecx, [task_queue]
	DEBUG	"pivot"
	DEBUGS	[ecx + edx + task_label]
	push	eax
	mov	eax, [ecx + edx + task_label]
	call	strlen
	neg	eax
	add	eax, 6
	jle	101f
100:	call	printspace
	dec	eax
	jg	100b
101:	pop	eax
	DEBUG_DWORD ebp,"esp"
	DEBUG_DWORD [ebp + task_reg_cs],"cs"
	DEBUG_DWORD [ebp + task_reg_eip],"eip"
	DEBUG_DWORD [ebp + task_reg_eflags],"eflags"
	call	newline
	pop	ebp
.endif
.endm

SCHEDULE_PRINT_FREQUENCY = 5 #PIT_FREQUENCY	# in Hz
.data SECTION_DATA_BSS
schedule_top_delay$: .long 0
.text32

.macro DO_SCHEDULER_DEBUG_TOP
	pushf

.if 1 	# print throttling
	push	eax
	add	dword ptr [schedule_top_delay$], SCHEDULE_PRINT_FREQUENCY
	mov	eax, [schedule_top_delay$]
	sub	eax, [pit_timer_frequency]
	jb	100f
	mov	[schedule_top_delay$], eax
100:	pop	eax
	jc	101f
.endif

	push	eax
	push	edx
	push	esi
	mov	bl, [schedule_show$]

	cmp	bl, 1
	jb	100f
	call	sched_print_graph

	cmp	bl, 2
	jb	100f
	PUSH_SCREENPOS 0
	# print mutex
	push	edx
	mov	edx, [mutex]
	call	printbin8
	pop	edx
	call	printspace
	# print task
	mov	eax, [scheduler_current_task_idx]
	add	eax, [task_queue]	# potential concurrency issue
	DEBUGS [eax + task_label],"task"
	POP_SCREENPOS

	cmp	bl, 3
	jb	100f
	call	schedule_print

100:	pop	esi
	pop	edx
	pop	eax


101:
	.if TASK_SWITCH_DEBUG > 1
		DEBUG "pivot"
		mov ebp, esp
		DEBUG_DWORD esp
		DEBUG_DWORD [ebp + task_reg_cs],"cs"
		DEBUG_DWORD [ebp + task_reg_eip],"eip"
		DEBUG_DWORD [ebp + task_reg_eflags],"eflags"
	.endif
	popf
.endm



# Not necessarily debug...
.if TASK_SWITCH_INTERVAL
.data SECTION_DATA_BSS
	schedule_delay$: .long 0
.text32
.endif

.macro DO_TASK_SWITCH_INTERVAL skiplabel=0
.if TASK_SWITCH_INTERVAL > 0
	push	ds
	push	eax
	mov	eax, SEL_compatDS
	mov	ds, eax
	inc	dword ptr [schedule_delay$]
	cmp	dword ptr [schedule_delay$], TASK_SWITCH_INTERVAL
	jae	100f
	pop	eax
	pop	ds
	.ifnc 0,\skiplabel
	jmp	\skiplabel
	.else
	iret
	.endif
100:	mov	dword ptr [schedule_delay$], 0
	pop	eax
	pop	ds
.endif
.endm

#############################################################################
scheduler_init:
	# assume scheduler is disabled: [task_queue_sem]==-1

	# clear fs, gs, since popping them in CPL > 0 causes error:
	xor	eax, eax
	mov	fs, eax
	mov	gs, eax

	# allocate a space for the current task:
	call	task_queue_newentry
	jc	9f

	mov	[scheduler_current_task_idx], edx
	LOAD_TXT "kernel"
	mov	[eax + edx + task_label], esi
	mov	[eax + edx + task_flags], dword ptr TASK_FLAG_RUNNING|TASK_FLAG_TASK
	mov	esi, [esp]
	mov	[eax + edx + task_registrar], esi
	mov	[eax + edx + task_stack_ss], ss # esp updated in scheduler

		LOAD_TXT "sched.debug"
		LOAD_TXT "0", edi
		mov	eax, offset scheduler_debug_var_changed
		add	eax, [realsegflat]
		mov	[edi], byte ptr '0' + SCHEDULE_DEBUG_TOP
		call	shell_variable_set

	mov	dword ptr [task_queue_sem], 0
	btr	dword ptr [mutex], MUTEX_SCHEDULER
	ret

9:	printlnc 4, "No more tasks"
	stc
	ret

# spinlock
scheduler_suspend:
	mov	ecx, 1000
0:	MUTEX_LOCK SCHEDULER, 1f
	mov	ecx, 1000
2:	SEM_SPINLOCK [task_queue_sem], locklabel=3f
	loop	2b
3:	ret
1:	loop	0b

scheduler_resume:
	mov	ecx, 1000
	SEM_UNLOCK [task_queue_sem]
0:	MUTEX_UNLOCK SCHEDULER
	ret

.data SECTION_DATA_BSS
schedule_show$: .byte 0
.text32
# in: eax = env var struct
scheduler_debug_var_changed:
	push	esi
	printc_ 11, "var changed: "
	mov	esi, [eax + env_var_label]
	call	print
	printcharc 11, '='
	mov	esi, [eax + env_var_value]
	call	print
	call	atoi_
	jc	9f
	cmp	eax, 9
	ja	9f
	mov	[schedule_show$], al
	OK
	pop	esi
	ret
9:	printlnc 4, " invalid value: not 0..9"
	pop	esi
	ret

#############################################################################

# in: [esp+4] = cs
# in: [esp+0] = eip
schedule_far:
	# shift stack down one word and inject esp
	sub	esp, 4	# esp+4=eip
	push	eax	# esp+8=eip
	mov	eax, [esp+8]	# eip
	mov	[esp + 4], eax
	mov	eax, [esp+12]	# cs
	mov	[esp + 8], eax
	pushfd
	pop	dword ptr [esp + 12]
	pop	eax
	jmp	schedule_isr

# scheduling disabled:
9:	DEBUG "Scheduling disabled: caller="
	push edx; mov edx, [esp]; call debug_printsymbol;pop edx
	hlt
	ret
# KEEP WITH NEXT!

# this is callable as a near call.
# in: [esp] = eip
schedule_near:
	cmp	dword ptr [task_queue_sem], -1
	jz	9b	# scheduling disabled...

	# adjust stack to make it suitable for iret

	push	eax
	mov	eax, cs
	and	al, 3	# check for privilege level change
	pop	eax
	jz	1f

	# enter kernel mode
	call	SEL_kernelMode, 0
.if 0
	DEBUG "kernelmode called."
	push ebp; lea ebp, [esp+4]
	DEBUG_DWORD [ebp+0]	# caller cs
	DEBUG_DWORD [ebp+4]	# caller esp
	DEBUG_DWORD [ebp+8]	# caller ss
	pop ebp
	call newline
.endif
	# now in CPL0.
	# Stack: kernelmode's caller cs, caller esp, caller ss.
	# copy the schedule_near caller's return address on the current
	# stack:
	sub	esp, 8	# reserve space for eip, eflags
	push	eax
	mov	eax, [esp + 4+8 +4]	# caller's esp
	# also pop the return address from the near caller's stack
	add	[esp + 4+8+4], dword ptr 4
	mov	eax, [eax]		# schedule_near caller eip
	mov	[esp + 4 + 0], eax		# eip
	# [esp+4+4]: should be cs, is undefined
	# [esp+4+8]: should be eflags, is cs
	mov	eax, [esp + 4 +8]
	mov	[esp + 4 +4], eax		# cs
	pushfd
	pop	eax
	mov	[esp + 12], eax		# eflags
	pop	eax

.if 0
	DEBUG "CPL0 schedule_near"
	push	ebp
	lea	ebp, [esp + 4]
	DEBUG_DWORD [ebp+0], "eip"
	DEBUG_DWORD [ebp+4], "cs"
	DEBUG_DWORD [ebp+8], "eflags"
	DEBUG_DWORD [ebp+12], "esp"
	DEBUG_DWORD [ebp+16], "ss"
call newline
	pop	ebp
.endif
	# stack is set up as if there was an interrupt with privilege level change.
	jmp	schedule_isr


# no privilege level change
1:	sub	esp, 8	# allocate eip,cs (eip on stack becomes eflags)
	push	eax
	mov	eax, [esp + 4 + 8]	# eip
	mov	[esp + 4], eax
	pop	eax
	mov	[esp + 4], cs
	pushf
	pop	dword ptr [esp + 8]
	#jmp	schedule_isr


# This method is called immediately after an interrupt is handled,
# and it is the tail part of the irq_proxy.
schedule_isr:
	.if SCHEDULE_JOBS
		jmp schedule_isr_TEST
	.endif
	DO_TASK_SWITCH_INTERVAL
	# store the CPU state (eip,cs,eflags already on stack):
	cli
	pushad
	pushd	ss
	pushd	ds
	pushd	es
	pushd	fs
	pushd	gs
	mov	ebp, esp
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax

	cmp	dword ptr [task_queue_sem], -1
	jz	10f

	MUTEX_LOCK SCHEDULER #, nolocklabel=9f
		DO_DEBUG_SCHEDULE_MUTEX
		jc	9f
	SEM_LOCK [task_queue_sem], nolocklabel=88f

	call	scheduler_get_task$

	or	dword ptr [eax + edx + task_flags], TASK_FLAG_RUNNING
	mov	[scheduler_current_task_idx], edx
	mov	[task_index], edx

	# since we've locked the task_queue sem, collapse eax and edx:
	add	edx, eax

# for debugging
mov ebx, [edx + task_stack]
mov ecx, [edx + task_stack+4]
# ! task cs=30 ss=a9, or a8: GPF.
	#lss	esp, [edx + task_stack]
	mov	esp, [edx + task_stack_esp]
	or	[esp + task_reg_eflags], dword ptr 1<<9

	mov	ebx, [edx + task_tls]
	mov	[tls], ebx

	SEM_UNLOCK [task_queue_sem]
8:	MUTEX_UNLOCK SCHEDULER
9:	# schedule mutex locked jmp target
	DO_SCHEDULER_DEBUG_TOP

10:	# scheduler disabled jmp target; CF=ZF=0
	popd	gs
	popd	fs
	popd	es
	popd	ds
#	popd	ss # should have same value as ss already has
	add	esp, 4	# the pushed ss is the task ss, which may have diff CPL
	popad	# esp ignored
	.if 0
		push	ebp
		lea	ebp, [esp + 4]
		DEBUG "continue"
		DEBUG_DWORD [ebp], "eip"
		DEBUG_DWORD [ebp+4], "cs"
		DEBUG_DWORD [ebp+8], "eflags"
		DEBUG_DWORD [ebp+12], "esp"
		DEBUG_DWORD [ebp+16], "ss"
		DEBUG_WORD ds
		DEBUG_WORD es
		call	newline
		pop	ebp

	.endif

	# two cases:
	# 1) same privilege level:
	#    [esp] = eip, cs, eflags
	# 2) different privilege level:
	#    [esp] = eip, cs, eflags, esp, ss
	iret

88:	SCHED_UPDATE_GRAPH 1
	jmp	8b

# precondition: [task_queue_sem] locked.
# out: eax + edx = runnable task
scheduler_get_task$:
	# update the current task's status

	mov	eax, [task_queue]
	mov	edx, [scheduler_current_task_idx]
	mov	[eax + edx + task_stack_esp], ebp	# preliminary

	# check for privilege level change
	mov	ebx, [ebp + 20+32+ 4]	# interrupted cs
	and	bl, 3
	jz	1f	# CPL0: okay

	# since there is privilege change, the task register's TSS SS0:ESP0
	# is used: it contains the eip,cs,eflags and esp,ss of interrupted
	# task, aswell as all the pushed registers.
	# We need to clear out this stack for subsequent use.

	# task_stack_esp points to the wrong stack:

	mov	esi, ebp	# source: the current (tss) stack
	mov	edi, [ebp + 20+32 + 12] # interrupted esp
	mov	ecx, 20+32+20	# pushseg[20],pushad[32],(eip,cs,eflags,esp,ss)[20]
	sub	edi, ecx
	# edi is the new task stack:
	mov	[eax + edx + task_stack_esp], edi
	shr	ecx, 2
	rep	movsd	# copy the entire pushed stack.

	# taskstack contains a copy of this stack, so we can use that
	# for a privchg iret, by using kernel ss, task esp.
	#
	# the stored esp used for privchg iret points to the same stack,
	# but, the ss will be the new priv level.
	# So, the task_stack_esp data looks like:
	#
	# S+20+32+20
	# S+20+32+16]	[4]  ss	 task ss
	# S+20+32+12	[4]  esp task esp, value S+20+32+20
	# S+20+32+8	[4]  eflags
	# S+20+32+4	[4]  cs	 task cs (CPL>0)
	# S+20+32	[4]  eip task interrupted instruction
	# S+20		[32] pushad
	# S		[20] push segment registers
	#(S = task_stack_esp)

1:
#########################################################################

	mov	ebx, [tls]
	mov	[eax + edx + task_tls], ebx
	.if 1
		# copy the register state - for debug
		# NOTE: if this is disabled, EIP doesn't get updated, and thus
		# tasks may be rejected due to them already being scheduled
		# (see schedule_task, task_is_queued). Tasks may still
		# be rejected when their first instruction is HLT under certain
		# conditions, even when this code is enabled.
		lea	edi, [eax + edx + task_regs]
		mov	esi, ebp
		mov	ecx, TASK_REG_SIZE
		rep	movsb
	.endif

	mov	ecx, [eax + array_index]	# 8 loop check

	test	[eax + edx + task_flags], dword ptr TASK_FLAG_DONE | TASK_FLAG_SUSPENDED
	jz	1f
2:	mov	[eax + edx + task_flags], dword ptr -1
	jmp	0f
1:	and	[eax + edx + task_flags], dword ptr ~TASK_FLAG_RUNNING

########
0:	add	edx, SCHEDULE_STRUCT_SIZE
	cmp	edx, [eax + array_index]
	jb	1f
	xor	edx, edx

1:	sub	ecx, SCHEDULE_STRUCT_SIZE	# 8 loop check
	js	9f

	test	dword ptr [eax + edx + task_flags], TASK_FLAG_DONE
	jnz	2b
	test	dword ptr [eax + edx + task_flags], TASK_FLAG_SUSPENDED
	jnz	0b
	test	dword ptr [eax + edx + task_flags], TASK_FLAG_RUNNING
	jnz	0b

	.if SCHEDULE_DEBUG_GRAPH
		mov	bl, 2
		cmp	edx, [scheduler_current_task_idx]
		jz	1f

		push eax
		mov eax, [eax + edx + task_label]
		mov eax, [eax]
		cmp eax, 'n'|'e'<<8|'t'<<16
		jnz 2f
		mov bl, 7
		pop eax; jmp 1f
		2: and eax, 0x00ffffff
		cmp eax, 'k'|'b'<<8
		jnz 2f
		mov bl, 6
		pop eax; jmp 1f
		2:pop eax

		inc	bl	# 3 = task switch
		test	dword ptr [eax + edx + task_flags], TASK_FLAG_TASK
		jz	1f
		inc	bl	# 4 = job
	1:	SCHED_UPDATE_GRAPH bl
	.endif

	.if TASK_SWITCH_DEBUG > 2
		or	edx, edx
		jz	1f
		DEBUGS [eax + edx + task_label]
	1:
	.endif

	ret
# 8 loop handler
9:	printlnc 4, "Task queue empty"
	call	cmd_tasks
	int 3
	jmp 	halt

##########################################################################
1:	pushad
	DO_SCHEDULER_DEBUG_TOP
	popad
	iret

schedule_isr_TEST:
	DO_TASK_SWITCH_INTERVAL #skiplabel=1b
#cli
	# store the CPU state (eip,cs,eflags already on stack):
	pushad
	pushd	ss
	pushd	ds
	pushd	es
	pushd	fs
	pushd	gs
	mov	ebp, esp
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax

	# prevent reentrancy
	MUTEX_LOCK SCHEDULER
	DO_DEBUG_SCHEDULE_MUTEX
	jc	9f	# XXX this line appears in exception stack!

	# lock the task queue array, prevent mrealloc and other updates:
	SEM_LOCK [task_queue_sem], 7f

		mov	eax, [task_queue]
		mov	edx, [scheduler_current_task_idx]
		# update stack
		mov	[eax + edx + task_stack_esp], ebp

		mov	ebx, [tls]
		mov	[eax + edx + task_tls], ebx

		# copy the register state
		lea	edi, [eax + edx + task_regs]
		mov	esi, ebp
		mov	ecx, TASK_REG_SIZE
		rep	movsb


	call	task_queue_get$	# out: ecx+edx
	jc	6f

	mov	eax, [scheduler_current_task_idx]

	test	[ecx + eax + task_flags], dword ptr TASK_FLAG_DONE
	jz	1f
	mov	[ecx + eax + task_flags], dword ptr -1 # mark as available
	jmp	2f
1:	and	[ecx + eax + task_flags], dword ptr ~TASK_FLAG_RUNNING
2:

.if SCHEDULE_JOBS

	test	[ecx + edx + task_flags], dword ptr TASK_FLAG_TASK
	jnz	1f

######## job
		.if TASK_SWITCH_DEBUG > 2
			DEBUG "JOB"
			DEBUGS [ecx+eax +task_label],"continuation"
			DEBUG_DWORD [ebp + task_reg_eip],"eip"
			DEBUG_DWORD ebp
			call newline
		.endif


	# leave current task 'running' so it won't be scheduled.
	or	dword ptr [ecx + eax + task_flags], TASK_FLAG_CHILD_JOB
	or	dword ptr [ecx + edx + task_flags], TASK_FLAG_RUNNING
	mov	[ecx + edx + task_parent], eax
	# prepare task stack: inject call
	push	eax # [scheduler_current_task_idx]
	push	edx
	push	dword ptr offset job_done	# catch job's "ret"
	# copy job context to current stack:
	push	dword ptr [ebp + task_reg_eflags]
	mov	esi, cs	# doing it this way, otherwise 0x00060030 gets pushed.
	push	esi
	push	dword ptr [ecx + edx + task_regs+task_reg_eip]

	mov	[ecx + edx + task_regs + task_reg_esp], esp
	mov	[ecx + edx + task_regs + task_reg_ss], ss

	lea	esi, [ecx + edx + task_regs]
	mov	ecx, TASK_REG_SIZE - 12
	sub	esp, ecx
	mov	edi, esp
	rep	movsb

	mov	ecx, [task_queue]

	mov	[ecx + edx + task_stack_esp], esp
	mov	[ecx + edx + task_stack_ss], ss

		.if TASK_SWITCH_DEBUG > 3
			pushad
			mov	ebx, eax
			mov	eax, ecx
			printcharc 0xf0, 'P'
			push	edx
			call	task_print$
			pop	edx
			printcharc 0xf0, 'C'
			mov	ebx, edx
			call	task_print$
			popad
		.endif

	jmp	2f

.endif
######## task

1:	lss	esp, [ecx + edx + task_stack]

	mov	ebx, [eax + edx + task_tls]
	mov	[tls], ebx

		.if TASK_SWITCH_DEBUG > 2
			DEBUG "TASK"
		.endif

	# update current task's status: (continuation)
	mov	[ecx + eax + task_stack_esp], ebp
	mov	[ecx + eax + task_stack_ss], ss
	# copy eip/esp in job context for easy checking/printing
	mov	ebx, [ebp + task_reg_eip]
	mov	[ecx + eax + task_regs + task_reg_eip], ebx
	lea	ebx, [ebp + task_reg_eip]
	mov	[ecx + eax + task_regs + task_reg_esp], ebx

	# mark new task as current:
	or	[ecx + edx + task_flags], dword ptr TASK_FLAG_RUNNING

2:

########

# in: ecx + edx = current task
# in: ecx + eax = prev task
# in: esp = task context (TASK_REG...)
pivot:
	mov	[scheduler_current_task_idx], edx
	or	[ecx + edx + task_flags], dword ptr TASK_FLAG_RUNNING
	or	[esp + task_reg_eflags], dword ptr 1<<9	# 'sti'

	DO_SCHEDULER_DEBUG_PIVOT


6:	SEM_UNLOCK [task_queue_sem]
7:	MUTEX_UNLOCK SCHEDULER
9:
	DO_SCHEDULER_DEBUG_TOP

	popd	gs
	popd	fs
	popd	es
	popd	ds
	popd	ss # should have same value as ss already has
	popad	# esp ignored
	iret

.if SCHEDULE_JOBS

# this is called when a scheduled job is done executing - the address
# is injected onto the stack of the task that will run the job.
job_done:
0:	MUTEX_LOCK SCHEDULER, nolocklabel=0b
0:	SEM_SPINLOCK [task_queue_sem], nolocklabel=0b

	mov	ecx, [task_queue]
	pop	edx	# job (child)
	pop	eax	# task (parent)
	.if TASK_SWITCH_DEBUG_JOB
		DEBUGS [ecx + edx + task_label], "job done"
	.endif

	.if TASK_SWITCH_DEBUG_JOB > 1
		DEBUGS [ecx+edx+task_label]
		DEBUG "->"
		DEBUGS [ecx+eax+task_label]
		DEBUG_DWORD esp
		DEBUG "->"
		lea	ebx, [esp + TASK_REG_SIZE - 12]
		DEBUG_DWORD ebx,"esp"
	.endif

	or	[ecx + edx + task_flags], dword ptr -1 # TASK_FLAG_DONE # -1
	and	[ecx + eax + task_flags], dword ptr ~TASK_FLAG_CHILD_JOB
	mov	edx, eax

	jmp	pivot	# the stack contains the task continuation
.endif


task_done:
0:	MUTEX_LOCK SCHEDULER, nolocklabel=0b
0:	SEM_SPINLOCK [task_queue_sem], nolocklabel=0b

	mov	edx, [esp]
	mov	eax, [task_queue]
	.if TASK_SWITCH_DEBUG_TASK
		DEBUGS [eax + edx + task_label], "done"
	.endif
	or	[eax + edx + task_flags], dword ptr TASK_FLAG_DONE

	SEM_UNLOCK [task_queue_sem]
	MUTEX_UNLOCK SCHEDULER

	pushf
	pushd	cs
	push	dword ptr offset 0f
	jmp	schedule_isr

	# in case the scheduler is locked (TASK_SWITCH_INTERVAL>0 for instance)
task_done_:	# debug label: nice output in task list
0:	printchar '.'
	YIELD
	jmp	0b




#############################################################################
# Task Queue

# out: eax + edx
# out: CF
task_queue_newentry:
	# find empty slot
	ARRAY_LOOP [task_queue], SCHEDULE_STRUCT_SIZE, eax, edx, 2f
	cmp	dword ptr [eax + edx + task_flags], -1
	jz	1f
	ARRAY_ENDL
2:	ARRAY_NEWENTRY [task_queue], SCHEDULE_STRUCT_SIZE, 4, 1f
1:	ret


# in: edx = task index
task_unqueue:
	mov	eax, [task_queue]
	mov	[eax + edx + task_flags], dword ptr -1

	# if it's the last entry, reduce array_index
	add	edx, SCHEDULE_STRUCT_SIZE
	cmp	edx, [ecx + array_index]
	jnz	1f
	sub	dword ptr [ecx + array_index], SCHEDULE_STRUCT_SIZE
1:	ret


# in: ebx = job eip
# out: ecx = how many times it is queued
# out: CF = task is queued
task_is_queued:
	xor	ecx, ecx
	ARRAY_LOOP [task_queue], SCHEDULE_STRUCT_SIZE, eax, edx, 2f
	test	[eax + edx + task_flags], dword ptr TASK_FLAG_DONE
	jnz	1f
	cmp	[eax + edx + task_regs + task_reg_eip], ebx
	jnz	1f
	inc	ecx
	.if SCHEDULE_DEBUG > 1
		DEBUG "<< DUP TASK:"
		DEBUGS [eax + edx + task_label]
		DEBUG ">>"
	.endif
1:	ARRAY_ENDL
2:	clc
	jecxz	1f
	stc
1:	ret


#############################################################################
.if SCHEDULE_ROUND_ROBIN
.data SECTION_DATA_BSS
task_index: .long 0
.text32
.endif

# NOTE: no locking is done - be sure to lock [task_queue_sem] around calling
# this method and using the pointers it returns!
#
# out: ecx + edx = task (ecx=[task_queue])
# out: CF = 1: no task
task_queue_get$:
	mov	ecx, [task_queue]
	or	ecx, ecx
	jz	1f
.if SCHEDULE_ROUND_ROBIN
	# increment task index for round robin
	mov	eax, [task_index]
	add	eax, SCHEDULE_STRUCT_SIZE
	cmp	eax, [ecx + array_index]
	jb	2f
	xor	eax, eax
	# sub
#	jns	2f
#	mov	eax, [ecx + array_index]
#	sub	eax, SCHEDULE_STRUCT_SIZE
2:	mov	[task_index], eax
	mov	edx, eax
.else
	# one-shot first-in-list
	xor	edx, edx	# index
.endif
########
0:	test	[ecx + edx + task_flags], dword ptr TASK_FLAG_RUNNING
	jz	0f
########

	add	edx, SCHEDULE_STRUCT_SIZE
.if SCHEDULE_ROUND_ROBIN
	cmp	edx, [task_index]
	jz	1f
.endif
	cmp	edx, [ecx + array_index]
	jb	0b
.if SCHEDULE_ROUND_ROBIN
	xor	edx, edx
	cmp	edx, [task_index]
	jnz	0b
.endif
########
1:	SCHED_UPDATE_GRAPH 2
	stc
	jmp	1f	# no task

######## found a job or task
0:
.if SCHEDULE_ROUND_ROBIN
	mov	[task_index], edx
.endif
	# null check:
	mov	eax, [ecx + edx + task_regs + task_reg_eip]
	or	eax, eax
	jnz	2f
	printc 4, "ERROR: scheduled task address NULL: "
	DEBUG_DWORD edx
	DEBUGS [ecx + edx + task_label]

	printc 4, " registrar: "
	push	edx
	mov	edx, [ecx + edx + task_registrar]
	call	printhex8
	call	newline
	pop	edx
	mov	[ecx + edx + task_regs + task_reg_eip], dword ptr -1
	mov	[ecx + edx + task_flags], dword ptr -1
	SCHED_UPDATE_GRAPH 5
	stc
	jmp	1f
########
2:	##
	SCHED_UPDATE_GRAPH 3
	clc

########
#	add	edx, ebx
	#mov	ebx, -1	# mark as free
	#xchg	ebx, [edx + task_flags]
	# mark as 'pending'; continuatoin may be scheduled,
	# using the src stack, so the data cannot be copied yet
	# over that stack before scheduling continuation.
	# scheduling continuatio nhwoever can also not overwrite
	# this task yet.
	# Set to -1 once data is copied.
#	or	dword ptr [ecx + edx + task_flags], 0x88000000
	mov	ebx, [ecx + edx + task_flags]

	.if TASK_SWITCH_DEBUG > 1
		DEBUG "TASK:"
		DEBUG_DWORD [ecx + edx + task_flags]
		DEBUG_DWORD [ecx + edx + tasK_regs + task_reg_eip]
		DEBUG_DWORD [ecx + edx + task_regs + task_reg_esp]
		DEBUG_DWORD ebx, "flags"
	.endif
	clc
1:	ret

9:	SCHED_UPDATE_GRAPH 1
	stc
	ret


#############################################################################


# This method is typically called in an ISR.
# Calling convention: stdcall:
#	PUSH_TXT "task name"
#	push	dword ptr 0|1	# flags
#	push	cs
#	.if [realsegflat] == 0
#	push	dword ptr offset task
#	.else
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
#	.endif
# in: [esp + 4]: eip - address of task
# in: [esp + 8]: cs - code seg of task
# in: [esp + 12]: task flags
# in: [esp + 16]: label for task
# in: all registers are preserved and offered to the task.
# out: eax = pid
# calling convention: stdcall [rtl, callee (this method) cleans stack]
schedule_task:
	cmp	dword ptr [task_queue_sem], -1
	jz	8f
	# copy regs to stack
	pushad
	pushd	ss
	pushd	ds
	pushd	es
	pushd	fs
	pushd	gs
	mov	ebp, esp
	# just in case:
	mov	eax, SEL_compatDS
	mov	ds, eax
	mov	es, eax

	SEM_SPINLOCK [task_queue_sem], nolocklabel=99f

	# duplicate schedule check: allow multiple instances of same task
	test	dword ptr [ebp + TASK_REG_SIZE - 12 + 12], TASK_FLAG_TASK
	jnz	1f	# no
	# check whether job is already scheduled
	mov	ebx, [ebp + TASK_REG_SIZE - 12 + 4]	# eip
	call	task_is_queued	# out: ecx
	.if 0
	jc	88f	# already queued
	.else	# allow one duplicate task
	jnc	1f
	# already queued, check if asked for duplicate:
	test	dword ptr [ebp + TASK_REG_SIZE - 12 + 12], TASK_FLAG_RESCHEDULE
	jz	88f	# no
	dec	ecx	# only one duplicate allowed
	jnz	88f
	.endif
1:

	call	task_queue_newentry
	jc	77f

	mov	ebx, eax	# using lodsd: free eax
	# copy registers
	lea	edi, [ebx + edx + task_regs]
	mov	esi, ebp
	mov	ecx, TASK_REG_SIZE - 12	# eip, cs, eflags not copied
	rep	movsb
	add	esi, 4	# skip method return
	movsd	# eip
	.if 1
	# calculate the selectors to use according to CPL.
	lodsd	# cs
	mov	eax, [esi] # task flags
	and	eax, TASK_FLAG_RING_MASK
	shr	eax, TASK_FLAG_RING_SHIFT - 4	# eax = 16 * RPL = 2 selectors
	mov	ecx, eax
	shr	ecx, 4	# remember RPL
	add	eax, SEL_ring0CS
	or	al, cl	# add RPL
	stosd	# cs

	.if 0
		DEBUG "schedule_task: "
		push esi; mov esi, [esi+4]; call print;pop esi
		call newline
		call printspace
		pushad;PRINT_GDT cs,1;popad
		pushad;PRINT_GDT eax,1;popad
		add	eax, 8
		call printspace
		pushad;PRINT_GDT ds,1;popad
		pushad;PRINT_GDT eax,1;popad
	.else
	add	eax, 8
	.endif

	mov	[ebx + edx + task_regs + task_reg_ds], eax
	mov	[ebx + edx + task_regs + task_reg_es], eax
	mov	[ebx + edx + task_regs + task_reg_ss], eax
	.else
	movsd	# cs
	.endif

	pushfd	# need some eflags
	pop	eax
	or	eax, 1 << 9	# sti
	mov	dword ptr [ebx + edx + task_regs + task_reg_eflags], eax

	lodsd	# task flags
	and	eax, TASK_FLAG_TASK | TASK_FLAG_RING_MASK
	mov	[ebx + edx + task_flags], eax
	lodsd	# task tabel
	mov	[ebx + edx + task_label], eax
	mov	eax, [ebp + task_reg_eip]	# method return, conveniently
	mov	[ebx + edx + task_registrar], eax
	mov	eax, [pid_counter]
	inc	dword ptr [pid_counter]
	mov	[ebx + edx + task_pid], eax

	.if SCHEDULE_JOBS == 0
	# jobs disabled, alloc stack always
	or	dword ptr [ebx + edx + task_flags], TASK_FLAG_TASK
	.else
	test	dword ptr [ebx + edx + task_flags], TASK_FLAG_TASK
	jz	7f
	.endif
	# check if the entry already has a stack
	mov	eax, [ebx + edx + task_stackbuf]
	or	eax, eax
	jnz	1f
	# allocate a stack
	mov	eax, JOB_STACK_SIZE
	call	mallocz
	jc	66f
#### debugging:
cmp eax, 0x00200000
jb 2f
int 3
2:
####
	mov	[ebx + edx + task_stackbuf], eax
1:

#### debugging
cmp eax, 0x00200000
jb 1f
int 3	# The bug is here. The task_stackbuf gets overwritten with at least
	# 4 bytes of root/www/index.html.
#### XXXBUG
1:
	.if SCHEDULE_CLEAN_STACK
	push	eax
	mov	edi, eax
	mov	ecx, JOB_STACK_SIZE / 4
	xor	eax, eax
	rep	stosd	# BUG: edi
	pop	eax
	.endif

	add	eax, JOB_STACK_SIZE
	and	eax, ~0xf

	# prepare stack
	.if SCHEDULE_JOBS == 0
	sub	eax, 8
	mov	[eax + 4], edx
	mov	[eax], dword ptr offset task_done
	.endif

	add	ebx, edx	# free up edx
	movzx	edx, word ptr [ebx + task_regs + task_reg_ds]

	sub	eax, TASK_REG_SIZE

	# if there is a privilege level change (from 0), alloc esp,ss
	test	dword ptr [ebx + task_flags], TASK_FLAG_RING_MASK
	jz	1f
	sub	eax, 8
1:

	# record stack for task switching
	mov	[ebx + task_stack_esp], eax
	mov	[ebx + task_stack_ss], edx # ss
	# copy the task registers from task struct to stack
	# (can be optimized
	mov	edi, eax
	lea	esi, [ebx + task_regs]
	mov	ecx, TASK_REG_SIZE / 4
	rep	movsd

.if 1
	test	dword ptr [ebx + task_flags], TASK_FLAG_RING_MASK
	jz	1f
	# privilege level change: push esp,ss
	#mov	[edi + 4], edx	# ss
	#add	edi, 8
	#mov	[edi - 8], edi
	## FOO
	#add	eax, 8
	push eax
	lea eax, [edi + 8]
	stosd
	mov eax, edx
	stosd
	pop eax
1:
.endif

.if 0
mov ebp, [ebx + task_stack_esp]
DEBUG_DWORD ebp, "task_stack_esp"
call newline
DEBUG_DWORD [ebp+0], "gs"
DEBUG_DWORD [ebp+4], "fs"
DEBUG_DWORD [ebp+8], "es"
DEBUG_DWORD [ebp+12], "ds"
DEBUG_DWORD [ebp+16], "ss"
call newline
add	ebp, 20 + 32
DEBUG_DWORD [ebp+0], "eip"
DEBUG_DWORD [ebp+4], "cs"
DEBUG_DWORD [ebp+8], "eflags"
DEBUG_DWORD [ebp+12], "esp"
DEBUG_DWORD [ebp+16], "ss"
call newline
#DEBUG "press key"
#push eax; xor eax,eax; call keyboard; pop eax
.endif

	add	eax, TASK_REG_SIZE - 12

	mov	[ebx + task_regs + task_reg_esp], eax
	mov	[ebx + task_regs + task_reg_ss], edx # ss

	mov	eax, [ebx + task_pid]
	mov	[ebp + task_reg_eax], eax

	clc
########
7:	pushf
	SEM_UNLOCK [task_queue_sem]
	popf

9:	popd	gs
	popd	fs
	popd	es
	popd	ds
	popd	ss
	popad
	ret	16
########
8:	test	[esp + 12], dword ptr TASK_FLAG_TASK
	jz	1f	# don't print for kernel jobs
	DEBUG "scheduling disabled: caller="
	push	edx
	mov	edx, [esp + 4]
	call	printhex8
	pop 	edx
	call	newline
1:	stc
	ret	16
######## error messages
99:	call	0f
	printlnc_ 4, "can't lock task queue"
	stc
	jmp	9b

88:	test	[ebp + TASK_REG_SIZE - 12 + 12], dword ptr TASK_FLAG_TASK
	stc
	jz	7b	# don't print for kernel jobs
	call	0f
	printlnc_ 4, "task already scheduled"
	stc
	jmp	7b

77:	call	0f
	printlnc_ 4, "can't allocate task entry"
	stc
	jmp	7b

66:	call	0f
	printlnc_ 4, "can't allocate task stack"
	stc
	jmp	7b

0:	printc_ 4, "schedule_task: "
	ret


task_get_by_pid:
	ARRAY_LOOP [task_queue], SCHEDULE_STRUCT_SIZE, ebx, ecx, 9f
	cmp	eax, [ebx + ecx + task_pid]
	jz	1f
	ARRAY_ENDL
	stc
1:	ret

# in: eax = pid
suspend_task:
	push	ebx
	push	ecx
	call	task_get_by_pid
	jc	9f
	or	dword ptr [ebx + ecx + task_flags], TASK_FLAG_SUSPENDED
9:	pop	ecx
	pop	ebx
	ret

# in: eax = pid
continue_task:
	push	ebx
	push	ecx
	call	task_get_by_pid
	jc	9f
	and	dword ptr [ebx + ecx + task_flags], ~TASK_FLAG_SUSPENDED
9:	pop	ecx
	pop	ebx

##############################################################################
##############################################################################
##############################################################################
# Debugging methods: 'graph'

.if SCHEDULE_DEBUG_GRAPH
.data SECTION_DATA_BSS
sched_graph: .space 80	# scoller
.data
sched_graph_symbols:
	.byte ' ', 0	# 0: no scheduling
	.byte '-', 0x4f # 1: lock fail
	.byte '-', 0x3f # 2: no task switch
	.byte '+', 0x3f # 3: task switch
	.byte '+', 0x2e # 4: job switch
	.byte 'x', 0xf4	# 5: fail to schedule
	.byte 'k', 0x0f # 6: keyboard
	.byte 'n', 0x0f # 7: net
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
	pop	edi
	pop	esi
	pop	ecx
	ret

sched_print_graph:
	push	ecx
	push	esi
	push	edi
	push	eax
	PUSH_SCREENPOS 0
	PRINT_START
	xor	eax, eax

#	cmp	byte ptr [schedule_show$], 2
#	jb	1f
#	mov	esi, offset sched_graph + 18
#	mov	edi, 18*2
#	mov	ecx, 80 - 18
#	jmp	0f
1:	mov	esi, offset sched_graph
	mov	ecx, 80

0:	lodsb
	and	al, 7
	xor	ah, ah
	mov	ax, [sched_graph_symbols + eax * 2]
	stosw
	loop	0b
	PRINT_END
	POP_SCREENPOS
	pop	eax
	pop	edi
	pop	esi
	pop	ecx
	ret
.endif



#############################################################################
# Task/schedule printing (ps, top)
#
TASK_PRINT_DEAD_JOBS	= 1	# completed tasks/jobs are printed
TASK_PRINT_RAW_FLAGS	= 0
TASK_PRINT_2		= 0	# PARENT|EFLAGS, TLS|REGISTRAR
TASK_PRINT_PARENT	= SCHEDULE_JOBS
TASK_PRINT_TLS		= 1

TASK_PRINT_SOURCE_LINE	= 1
TASK_PRINT_BG_COLOR = 0x10

schedule_print:
	push	eax
	push	ebx
	push	ecx
	push	edx
	push	esi
	push	edi

	PUSH_SCREENPOS 160*1
	mov	ecx, 80 * 10
	PRINT_START TASK_PRINT_BG_COLOR, ' '
	rep	stosw
	PRINT_END
	POP_SCREENPOS

	PUSH_SCREENPOS 160*1
	pushfd
	pop edx
	DEBUG_DWORD edx, "FLAGS"
	DEBUG_DWORD [ebp+task_reg_eflags]
	call printspace

	call	cmd_tasks

	POP_SCREENPOS
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret

#############################################################################

cmd_tasks:
	pushcolor TASK_PRINT_BG_COLOR | 7
	print_ "Tasks: "
	mov	ecx, [task_queue]
	or	ecx, ecx
	jz	9f
	mov	ebx, SCHEDULE_STRUCT_SIZE
	xor	edx, edx
	mov	eax, [scheduler_current_task_idx]
	div	ebx
	mov	edx, eax
	call	printdec32
	printchar_ '/'
	xor	edx, edx
	mov	eax, [ecx + array_index]
	div	ebx
	mov	edx, eax
	call	printdec32
.if SCHEDULE_JOBS
.if SCHEDULE_ROUND_ROBIN
	print_ " sched idx: "
	mov	eax, [task_index]
	xor	edx, edx
	div	ebx
	call	printdec32
.endif
.endif
	call	newline

	call	task_print_h$

	printc_ TASK_PRINT_BG_COLOR | 15, "C "	# for current, see
	mov	eax, [task_queue]
	mov	ebx, [scheduler_current_task_idx]
	call	task_print$
	call	newline

	xor	ecx, ecx # index counter, saves dividing ebx by SCHED_STR_SIZE
	ARRAY_LOOP [task_queue], SCHEDULE_STRUCT_SIZE, eax, ebx, 9f
	.if TASK_PRINT_DEAD_JOBS == 0	# default, to keep an eye on array reuse
	cmp	[eax + ebx + task_flags], dword ptr -1
	jz	3f
	.endif
	mov	edx, ecx
	cmp	ebx, [task_index]
	jnz	1f
	color	TASK_PRINT_BG_COLOR | 15
1:	call	printdec32
	color	TASK_PRINT_BG_COLOR | 7
	call	printspace

	cmp	ebx, [scheduler_current_task_idx]
	jnz	1f
	color	TASK_PRINT_BG_COLOR | 15
	jmp	2f

1:	cmp	[eax + ebx + task_flags], dword ptr -1
	jnz	2f
	color	TASK_PRINT_BG_COLOR | 8

2:	call	task_print$
3:	inc	ecx
	ARRAY_ENDL
9:	popcolor
	ret



task_print_h$:
.data SECTION_DATA_STRINGS	# a little kludge to keep the string from wrappi
200:
.ascii " idx pid. addr.... stack... flags... "
.if TASK_PRINT_2
.if TASK_PRINT_TLS;	.ascii "tls..... "; .else; .ascii "registrr "; .endif
.if TASK_PRINT_PARENT;	.ascii "parent.. "; .else; .ascii "eflags.. "; .endif
.asciz "label, symbol"
.else
.asciz "label... symbol"
.endif
.text32
	mov	ah, TASK_PRINT_BG_COLOR | 11
	mov	esi, offset 200b
	call	printlnc
	ret

# in: eax + ebx = task
task_print$:
	pushad

	xor	edx, edx
	push	eax
	push	ecx
	mov	ecx, SCHEDULE_STRUCT_SIZE
	mov	eax, ebx
	div	ecx
	mov	edx, eax
	pop	ecx
	pop	eax
	call	printhex2
	call	printspace

	mov	edx, [eax + ebx + task_pid]
	call	printhex4
	call	printspace
	mov	edx, [eax + ebx + task_regs + task_reg_eip]
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + task_stack_esp]#task_regs + task_reg_esp]
	call	printhex8
	call	printspace
	mov	edx, [eax + ebx + task_flags]
	.if TASK_PRINT_RAW_FLAGS
	call	printhex8
	.else
	cmp	edx, -1
	jnz	1f
	print "........"
	jmp	2f
1:	PRINTFLAG edx, TASK_FLAG_RUNNING,	"R", " "
	PRINTFLAG edx, TASK_FLAG_SUSPENDED,	"S", " "
	PRINTFLAG edx, TASK_FLAG_DONE,		"D", " "
	PRINTFLAG edx, TASK_FLAG_CHILD_JOB,	"C", " "
	PRINT " "
	PRINTFLAG edx, TASK_FLAG_RESCHEDULE,	"r", " "
	PRINTFLAG edx, TASK_FLAG_TASK,		" T", "J "
2:
	.endif
	call	printspace
.if TASK_PRINT_2
	.if TASK_PRINT_TLS
	mov	edx, [eax + ebx + task_tls]
	.else
	mov	edx, [eax + ebx + task_registrar]
	.endif
	call	printhex8
	call	printspace
	.if TASK_PRINT_PARENT
		.if 1
			mov	edx, [eax + ebx + task_parent]
			mov	edx, [eax + edx + task_pid]
			call 	printhex8
		.else
			push	eax
			push	ebx
			mov	eax, [eax + ebx + task_parent]
			xor	edx, edx
			mov	ebx, SCHEDULE_STRUCT_SIZE
			div	ebx
			mov	edx, eax
			call	printhex8
			pop	ebx
			pop	eax
		.endif
	.else
		mov	edx, [eax + ebx + task_regs + task_reg_eflags]
		call	printhex8
	.endif
	call	printspace
.endif
	mov	esi, [eax + ebx + task_label]
	call	print
	call	printspace
	# print address symbols: calculate space
	call	strlen_
	neg	ecx
.if TASK_PRINT_2
	add	ecx, 17+7-1	# space + label
.else
	add	ecx, 8
	jle	1f
0:	call	printspace
	loop	0b
1:	add	ecx, 80-37-8
.endif

	mov	edx, [eax + ebx + task_regs + task_reg_eip]

	.if TASK_PRINT_SOURCE_LINE
	call	debug_getsource
	jc	1f
	pushcolor TASK_PRINT_BG_COLOR | 14
	PUSHCOLOR TASK_PRINT_BG_COLOR | 9
	call	nprint
	push	edx
	mov	edx, eax
	printchar_ ':'
	call	printdec32
	pop	edx
	POPCOLOR
	call	printspace
#	call	newline
#	jmp	9f
	popcolor
1:
	.endif

	call	debug_getsymbol
	jc	1f
	pushcolor TASK_PRINT_BG_COLOR | 14
	call	nprint
	call	newline
	popcolor
	jmp	9f
1:	# no exact match, also print offset
	call	debug_get_preceeding_symbol
	jc	1f
	pushcolor TASK_PRINT_BG_COLOR | 13
	call	nprint
	push	edx
	mov	edx, ecx
	call	strlen_
	sub	edx, ecx
	cmp	edx, 1+4
	pop	edx
	jb	2f
	sub	edx, eax
	printchar_ '+'
	call	printhex4	# meaningful relative offsets are usually < 64k
2:	popcolor
1:	call	newline

9:	popad
	ret

#############################################################################
cmd_top:
	mov	al, [schedule_show$]
	push	eax
	call	cls
	mov	byte ptr [schedule_show$], 3

0:	#call	cls
	#call	newline
	#call	schedule_print
	#hlt
	#mov	ah, KB_PEEK
	#call	keyboard
	#jc	0b
	xor	ax, ax
	call	keyboard
	cmp	ax, K_ESC
	jz	0f
	cmp	ax, K_ENTER
	jnz	0b
0:	pop	eax
	mov	byte ptr [schedule_show$], al
	ret
#############################################################################
cmd_kill:
	lodsd
	lodsd	# CMD_EXPECTARG 9f
	or	eax, eax
	jz	9f
	mov	edx, [eax]
	lodsd
	and	edx, 0x00ffffff
	cmp	edx, '-'|'p'<<8
	jnz	1f
	call	htoi
	jc	9f
	mov	edx, eax

#	SEM_SPINLOCK [task_queue_sem], 8f	# destroys eax, ecx
	ARRAY_LOOP [task_queue], SCHEDULE_STRUCT_SIZE, ebx, ecx, 1f
	cmp	[ebx + ecx + task_pid], edx
	jz	2f
	ARRAY_ENDL
	jmp	1f

1:	cmp	edx, '-'|'i'<<8
	jnz	9f
	call	atoi
	jc	9f

	mov	ecx, SCHEDULE_STRUCT_SIZE
	imul	ecx, eax
#	SEM_SPINLOCK [task_queue_sem], 8f	# destroys eax, ecx
	mov	ebx, [task_queue]
	cmp	ecx, [ebx + array_index]
	jae	7f

2:	printc_ 11, "killing pid "
	mov	edx, [ebx + ecx + task_pid]
	call	printhex8
	printc_ 11, " '"
	mov	esi, [ebx + ecx + task_label]
	call	print
	printlnc_ 11, "'"
	or	[ebx + ecx + task_flags], dword ptr TASK_FLAG_DONE
1:#	SEM_UNLOCK [task_queue_sem]
	ret
7:	printlnc 4, "no such task"
	jmp	1b
8:	printlnc 4, "cannot lock task queue"
	ret
9:	printlnc_ 12, "usage: kill [-i <idx> | -p <hex pid>]"
	ret
