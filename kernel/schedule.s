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

.if DEFINE

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
task_flags:	.long 0
	# task configuration flags:
.endif
	TASK_FLAG_TASK		= 0x0001
	TASK_FLAG_RESCHEDULE	= 0x0010	# upon completion, sched again
	# task wait flags:
	TASK_FLAG_WAIT_IO	= 0x0100	# task waiting for IO
	TASK_FLAG_WAIT_MUTEX	= 0x0200	# task waiting for MUTEX avail
	# task status flags:
	TASK_FLAG_RUNNING	= 0x8000 << 16	# do not schedule
	TASK_FLAG_SUSPENDED	= 0x4000 << 16
	TASK_FLAG_DONE		= 0x0100 << 16	# (aligned with RESCHEDULE)
	TASK_FLAG_DONE_SHIFT	= 24	# for 'bt'
	# task creation option flags:
	TASK_FLAG_OPT_DEV_PCI	= 0x0020	# when given, pushd the PCI class first on calling schedule_task

	TASK_FLAG_CHILD_JOB	= 0x0010 << 16	# a job is using this stack
	TASK_FLAG_FLATSEG	= 0x0020 << 16

	TASK_FLAG_RING0		= 0x0000 << 16
	TASK_FLAG_RING1		= 0x0001 << 16
	TASK_FLAG_RING2		= 0x0002 << 16
	TASK_FLAG_RING3		= 0x0003 << 16
	TASK_FLAG_RING_MASK	= 0x0003 << 16
	TASK_FLAG_RING_SHIFT	= 16

	TASK_FLAG_RING_SERVICE = TASK_FLAG_RING2
.if DEFINE
	# using ring1 or ring2: paging distinguishes between CPL[012] and CPL3
	# using the "U" bit.
	# syscall would only work with ring0 and ring3.
task_parent:	.long 0
task_tls:	.long 0
task_stackbuf:	.long 0	# remembered for mfree
task_stack:
task_stack_esp:	.long 0
task_stack_ss:	.long 0
task_stack_esp0:.long 0	# stack for CPL0
task_stack_ss0:	.long 0
task_stack0_top:.long 0
task_stack0_bitindex: .long 0	# for debug
task_cr3:		# page directory physical address
task_page_dir:	.long 0	# for mfree_page_phys
task_page_tab_lo:.long 0 # for mfree_page_phys
task_page_tab_hi:.long 0 # for mfree_page_phys
task_io_sem_ptr:.long 0		#
task_io_sem_timeout:.long 0	# 'abs' clock_ms
	# task_can_run will probe the semaphore pointer value and exclude tasks from being able to be scheduled.
	# The 'SEM_UNLOCK' system call would set a flag that a semaphore was released
	# SEM_LOCK will also require a pointer here.
	# All tasks waiting for sem IO can be ordered,
	# by comparing the semaphore pointers. (or mutexes).
	# The semaphore code is fast-succeed, meaning,
	# no task switching occurs if the lock is successful.
	# If it fails the scheduler is informed.
	# The scheduler would also know all locked semaphores and which
	# tasks own them.
	# It can then increase the priority of the task holding
	# the semaphore.
	# 
	# The first iteration will filter out all suspended tasks.
	# Next, all tasks with a blocking IO (sem).
	# The remaining tasks will have priority adjusted depending
	# on whether they have unlocked a semaphore in the last
	# timeslot.
	# Once a task is scheduled, the priorities are reset.
	# (This comes down to calculating them by iterating all
	# tasks on each schedule pivot, and maintaining a max
	# heuristic and associated task.
	#
	# (sort { $a{prio} <=> $b{prio} } @tasks)[0]    
	
task_irq_service_pci_class: .byte 0, 0,0,0
	# Interrupt handlers such as device drivers notify
	# the scheduler via kernel APIs on the application data level
	# such as sempahore locking (MUTEX_SOCK, SEM_NETQ),
	# aswell as by being directly invoked after each IRQ.
	# We will assume that the device driver has arranged for
	# the kernel to buffer the data.
	#
	# The PCI device class of a NIC is an indication as to which
	# kind of task is involved. Any DEV_PCI_CLASS_NIC would
	# be associated with the netq kernel daemon, in charge of delivering
	# network packets to socket buffers.
	# 
	# Tasks such as netq would have to indicate all dev_irq values
	# for all device drivers, which means iterating over a list of lists.
	# Therefore the PCI class is used to indicate an architectural
	# association.
	# Similarly, DEV_PCI_SERIAL devices such as USB might invoke
	# the keyboard handler or media drivers.
	#
	# The value of the field describes the kind of service this task
	# performs, and is only (TODO) settable by CPL0.
	#
	# To have any device drivers' IRQ handler indicate an increased
	# likelyhood of such a service task needing to be scheduled,
	# all drivers must be registered using the DEV_PCI structure.
	#
	# The kernel (see idt.s) can keep track of interrupt service
	# routines. When an ISR is registered, ebx will be the device
	# base pointer, which is recorded (TODO/check).

task_time_start:.long 0, 0	# timestamp value on resume
task_time_stop:	.long 0, 0	# timestamp value on interrupted/suspended
task_time:	.long 0, 0	# total running time
task_schedcount:.long 0

task_cur_cr3:	.long 0
# these values are only used for jobs:
.align 4	# for movsd (future modifications)
task_regs:	.space TASK_REG_SIZE
.align 4
SCHEDULE_STRUCT_SIZE = .

.data
task_queue_sem:	.long -1	# -1: scheduling disabled
.global scheduler_current_task_idx
scheduler_current_task_idx: .long -1
scheduler_prev_task_idx: .long -1	# for debug

.data SECTION_DATA_BSS
pid_counter:	.long 0
task_queue:	.long 0
tls:		.long 0 # task/thread local storage (not SMP friendly perhaps?)
.tdata
tls_pid:	.long 0	# not used - no tls setup in this file.
tls_task_idx:	.long 0	# not used - no tls setup in this file.
.tdata_end


.data SECTION_DATA_STATS
.global stats_task_switches
stats_task_switches: .long 0
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

SCHEDULE_PRINT_FREQUENCY =  PIT_FREQUENCY	# in Hz
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
	add	eax, [task_queue]	# XXX potential concurrency issue
	DEBUGS [eax + task_label],"task"
	POP_SCREENPOS

	cmp	bl, 3
	jb	100f
	push ebp
	mov ebp, eax
	call	schedule_print
	pop ebp

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
	# not really needed, since the kernel task will run in CPL0
	mov	[eax + edx + task_stack_ss0], ss
	mov	esi, [TSS + tss_ESP0]
	mov	[eax + edx + task_stack_esp0], esi

	mov	esi, cr3
	mov	[eax + edx + task_cr3], esi
	mov	[eax + edx + task_cur_cr3], esi
	inc	dword ptr [pid_counter]

	# enable the scheduler

	mov	dword ptr [task_queue_sem], 0
	btr	dword ptr [mutex], MUTEX_SCHEDULER

		LOAD_TXT "sched.debug"
		LOAD_TXT "0", edi
		mov	eax, offset scheduler_debug_var_changed
		add	eax, [realsegflat]
		mov	[edi], byte ptr '0' + SCHEDULE_DEBUG_TOP
		call	shell_variable_set


	########
	# create idle task:
	PUSH_TXT "<idle>"
	push	dword ptr TASK_FLAG_TASK
	push	cs
	push	dword ptr offset idle_task
	call	schedule_task
	#call	task_suspend
	ret

9:	printlnc 4, "No more tasks"
	stc
	ret

idle_task:
	hlt
idle_task$:	# debug symbol
	jmp idle_task

# spinlock
scheduler_suspend:
	mov	ecx, 1000
0:	MUTEX_LOCK SCHEDULER, 1f
	mov	ecx, 1000
2:	SEM_SPINLOCK [task_queue_sem], locklabel=3f
	loop	2b
3:	ret
1:	loop	0b
# XXX was an undocumented FALLTHROUGH - probably bug:
	printlnc 4, "FAIL lock SCHEDULER mutex"
	int 3	# XXX
	jmp	scheduler_suspend

scheduler_resume:
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
	push edx; mov edx, [esp+4]; call printhex8;call printspace; call debug_printsymbol;pop edx
	hlt
	# This method is called from mutex/semaphore code. It will only
	# schedule when lock acquisition fails, which should not happen
	# when scheduling is dabled. (This code is called in other places
	# aswell, but generally speaking, this condition indicates a
	# programming error).
	int 3
	ret
# KEEP WITH NEXT! (9b)

# this is callable as a near call.
# in: [esp] = eip
KAPI_DECLARE yield
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
	# NOTE: the code called from the scheduler _MAY_ result in this code being
	# executed from within the ISR stack:
	# (task_update_time_* -> pit.s/get_time_ms_40->mutex->yield).
	# The solution there is to disable the scheduler around the mutex lock.
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
	# ignore CF: scheduler_init creates an idle task that can always run.

	or	dword ptr [eax + edx + task_flags], TASK_FLAG_RUNNING

	cmp	[scheduler_current_task_idx], edx
	mov	[scheduler_current_task_idx], edx
	jz	1f
	incd	[stats_task_switches]
	incd	[eax + edx + task_schedcount]
1:

	mov	[task_index], edx

lea ebx, [eax + edx]
call task_update_time_resume$
	# since we've locked the task_queue sem, collapse eax and edx:
	add	edx, eax

	#lss	esp, [edx + task_stack]
	# the stack here may not be paged if it is the elevated stack.
	# swap out to the kernel page dir
	mov	ebx, [page_directory_phys]
	mov	cr3, ebx

	mov	esp, [edx + task_stack_esp]
	or	[esp + task_reg_eflags], dword ptr 1<<9

	mov	ebx, [edx + task_tls]
	mov	[tls], ebx

	mov	ebx, [edx + task_stack_esp0]
	mov	[TSS + tss_ESP0], ebx

	mov	eax, [edx + task_cur_cr3]
	mov	cr3, eax

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


# in: eax = task idx
# PRECONDITION: [task_queue] locked
task_print_stack$:
#	DEBUG_DWORD eax, "task idx"
	add	eax, [task_queue]
	DEBUG_WORD [eax+task_pid],"PID"
#	DEBUG_DWORD [eax+task_flags],"flags"
	mov	esi, [eax + task_label]
#	DEBUG_DWORD esi
	cmp esi, 0x02000000
	jae 1f
	call	print
1:	mov	esi, [eax + task_stack_esp]
	DEBUG_DWORD esi, "stack_esp"
	lodsd; DEBUG_DWORD eax,"gs"
	lodsd; DEBUG_DWORD eax,"fs"
	lodsd; DEBUG_DWORD eax,"es"
	lodsd; DEBUG_DWORD eax,"ds"
	lodsd; DEBUG_DWORD eax,"ss"
	lodsd;#DEBUG_DWORD eax,"edi"
	lodsd;#DEBUG_DWORD eax,"esi"
	lodsd;#DEBUG_DWORD eax,"ebp"
	lodsd;#DEBUG_DWORD eax,"esp"
	lodsd;#DEBUG_DWORD eax,"ebx"
	lodsd;#DEBUG_DWORD eax,"edx"
	lodsd;#DEBUG_DWORD eax,"ecx"
	lodsd;#DEBUG_DWORD eax,"eax"
	lodsd; DEBUG_DWORD eax,"eip"
	lodsd; DEBUG_DWORD eax,"cs"
	lodsd; DEBUG_DWORD eax,"eflags"
	lodsd; DEBUG_DWORD eax,"esp"
	lodsd; DEBUG_DWORD eax,"ss"
	ret



# precondition: [task_queue_sem] locked.
# out: eax + edx = runnable task
# out: CF = 1 = no tasks can be run at this time: run idle task.
# modifies: ecx, ebx, esi, edi
scheduler_get_task$:
	# update the current task's status
	mov	eax, [task_queue]
	mov	edx, [scheduler_current_task_idx]
	mov	[scheduler_prev_task_idx], edx		# for debugging
	mov	[eax + edx + task_stack_esp], ebp	# preliminary
lea ebx, [eax + edx]
call task_update_time_suspend$
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
	mov	ebx, cr3
	mov	[eax + edx + task_cur_cr3], ebx

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
		mov	esi, [eax + edx + task_stack_esp]
		mov	ecx, TASK_REG_SIZE
		rep	movsb
	.endif


	test	[eax + edx + task_flags], dword ptr TASK_FLAG_DONE #| TASK_FLAG_SUSPENDED
	jz	1f
	lea	ebx, [eax + edx]
	call	task_cleanup$	# in: ebx
2:	mov	[eax + edx + task_flags], dword ptr -1
	jmp	0f
1:	and	[eax + edx + task_flags], dword ptr ~TASK_FLAG_RUNNING
0:

########
	mov	ecx, [eax + array_index]	# 8 loop check
	xor	ebx, ebx	# count non-completed tasks

0:	bt	dword ptr [eax + edx + task_flags], TASK_FLAG_DONE_SHIFT
	adc	ebx, 0

	add	edx, SCHEDULE_STRUCT_SIZE
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

	test	dword ptr [eax + edx + task_flags], TASK_FLAG_WAIT_IO
	jz	1f	# can schedule
	mov	edi, [eax + edx + task_io_sem_ptr]
	or	edi, edi
#	jz	92f	# no sem: error
	jz	3f	# no sem: simple timeout
	cmp	dword ptr [edi], 0
	jnz	2f	# have data
3:	mov	edi, [eax + edx + task_io_sem_timeout]
	cmp	[clock_ms], edi
	jb	0b
	# sem timeout, proceed.
2:
#	lock dec dword ptr [ebx] # leave this to the task
	and	dword ptr [eax + edx + task_flags], ~TASK_FLAG_WAIT_IO
1:

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
	clc
	ret
# 8 loop handler
9:	or	ebx, ebx
	jz	1f	# we have some tasks, none of which are schedulable
	stc
	ret

	# we have no tasks that can be scheduled.
1:	printlnc 4, "No schedulable tasks"
1:	call	cmd_ps$
	int 3
	jmp 	halt

92:	printlnc 4, "Task WAIT_IO without IO sem"
	jmp	1b

##########################################################################
1:	pushad
	DO_SCHEDULER_DEBUG_TOP
	popad
	iret


# out: ax
pit_read_time:
	pushf
	cli     # lock pit port
	mov     al, byte ptr PIT_CW_RW_CL | PIT_CW_SC_0
	out     PIT_PORT_CONTROL, al
	in      al, PIT_PORT_COUNTER_0
	mov     ah, al
	in      al, PIT_PORT_COUNTER_0
	popf
	ret

# NOTE: be certain that methods called here either disable the scheduler
# or not call yield (which is what MUTEX_SPINLOCK does).
#
# in: ebx = task ptr
task_update_time_suspend$:
	push_	eax edx esi edi
	mov	edi, [ebx + task_time_start+0]	# read start time
	mov	esi, [ebx + task_time_start+4]
	#rdtsc
	call	get_time_ms_40_24
	# edx:eax = now/stop
	# edi:esi = start
	mov	[ebx + task_time_stop+0], edx	# write end time (not needed)
	mov	[ebx + task_time_stop+4], eax
	# calc delta
	sub	eax, esi
	sbb	edx, edi
		jns 1f; printc 4, "NEGATIVE TIME"; 1:
	add	[ebx + task_time+4], eax	# write delta
	adc	[ebx + task_time+0], edx	
	pop_	edi esi edx eax
	ret

task_update_time_resume$:
	push_	eax edx
	#rdtsc	
	call	get_time_ms_40_24
	mov	[ebx + task_time_start+0], edx	# write start time
	mov	[ebx + task_time_start+4], eax
	pop_	edx eax
	ret



.if SCHEDULE_JOBS

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
	lea	ebx, [ecx + eax]
	call	task_cleanup$	# free stacks; in: ebx
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

.endif

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
	mov	ebx, [esp]	# task index

		mov eax, cs
		cmp eax, SEL_ring0CSf
		jb 1f
		add	eax, SEL_ring0CS - SEL_ring0CSf + 8
		# NOTE: making eax 0 will cause system hang, due to ds/es being cs...
		# (had expected a GPF).
		mov	ds, eax
		mov	es, eax
	1:
	KAPI_CALL task_exit	# does not return.
0:	print "."
	YIELD
	jmp	0b


# mark task as done
# in: ebx = task index
KAPI_DECLARE task_exit
task_exit:
#DEBUG_DWORD ebx,"TASK_EXIT idx", 0xf0
0:	MUTEX_LOCK SCHEDULER, nolocklabel=0b
0:	SEM_SPINLOCK [task_queue_sem], nolocklabel=0b

#	mov	ebx, [esp]
	mov	eax, [task_queue]
	.if TASK_SWITCH_DEBUG_TASK
		DEBUGS [eax + ebx + task_label], "done"
	.endif
	or	[eax + ebx + task_flags], dword ptr TASK_FLAG_DONE

	SEM_UNLOCK [task_queue_sem]
	MUTEX_UNLOCK SCHEDULER
	# invoke the scheduler
	YIELD
	printc 0x4f, "Zombie task scheduled!"
0:	hlt
	printchar_ '.'
	jmp	0b
	ret


# in: ebx = task
# PRECONDITION: task_queue_sem locked
task_cleanup$:
	push	eax
	mov	eax, [ebx + task_page_dir]
	call	mfree_page_phys
	mov	eax, [ebx + task_page_tab_lo]
	call	mfree_page_phys
	mov	eax, [ebx + task_page_tab_hi]
	call	mfree_page_phys

	test	dword ptr [ebx + task_flags], TASK_FLAG_RING_MASK
#	jz	1f
	mov	eax, [ebx + task_stack0_top]
	call	free_task_priv_stack
1:

	xor	eax, eax
	xchg	eax, [ebx + task_stackbuf]
	call	mfree
	pop	eax
	ret

.if 1
	pushf
	pushd	cs
	push	dword ptr offset 0f
	jmp	schedule_isr
.endif



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
2:	ARRAY_NEWENTRY [task_queue], SCHEDULE_STRUCT_SIZE, 4, 9f
	DEBUG "+", 0x4f
1:	push_	edi eax ecx
	lea	edi, [eax + edx]
	xor	eax, eax
	mov	ecx, SCHEDULE_STRUCT_SIZE / 4
	rep	stosd
	mov	[edi - SCHEDULE_STRUCT_SIZE + task_flags], dword ptr TASK_FLAG_SUSPENDED
	pop_	ecx eax edi
	ret
9:	printlnc 4, "task_queue_newentry: malloc fail"
	stc
	ret


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


.if SCHEDULE_JOBS

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
0:	call	task_can_run$	# out: CF = 0 = yes
	jnc	0f
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
	# mark as 'pending'; continuatoin may be scheduled,
	# using the src stack, so the data cannot be copied yet
	# over that stack before scheduling continuation.
	# scheduling continuatio nhwoever can also not overwrite
	# this task yet.
	# Set to -1 once data is copied.
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

# in: ecx + edx = task
# out: CF = 1 = no, CF = 0 = yes
task_can_run$:
	push	eax
	mov	eax, [ecx + edx + task_flags]

	test	eax, TASK_FLAG_RUNNING
	stc	# mark can't run
	jnz	9f	# already running (current task or SMP)

	test	eax, TASK_FLAG_WAIT_IO
	clc	# mark can run
	jz	9f	# no IO wait, can run

	mov	eax, [ecx + edx + task_io_sem_ptr]

	cmp	dword ptr [eax], 0
	stc
	jz	9f	# nope

	lock dec dword ptr [eax]
	and	dword ptr [ecx + edx + task_flags], ~TASK_FLAG_WAIT_IO
	# CF = 0

9:	pop	eax
	ret
.endif
#############################################################################


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
KAPI_DECLARE schedule_task, 4
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
	SEM_SPINLOCK [task_queue_sem], nolocklabel=99f

	# duplicate schedule check: allow multiple instances of same task
	test	dword ptr [ebp + TASK_REG_SIZE - 12 + 12], TASK_FLAG_TASK
	jnz	1f	# it's a task, not a job.
	# check whether job is already scheduled
	mov	ebx, [ebp + TASK_REG_SIZE - 12 + 4]	# eip
	call	task_is_queued	# out: ecx
	jnc	1f
	# already queued, check if asked for duplicate:
	test	dword ptr [ebp + TASK_REG_SIZE - 12 + 12], TASK_FLAG_RESCHEDULE
	jz	88f	# no
	dec	ecx	# only one duplicate allowed
	jnz	88f
1:

	call	task_queue_newentry	# out: eax + edx
	jc	77f
	lea	ebx, [eax + edx]

	call	task_setup_paging	# out: eax
	jc	55f

	# copy registers
	lea	edi, [ebx + task_regs]
	mov	esi, ebp
	mov	ecx, (TASK_REG_SIZE - 12)/4 # eip, cs, eflags not copied
	rep	movsd
	add	esi, 4	# skip method return
	movsd	# eip
	# calculate the selectors to use according to CPL.
	add	esi, 4	# cs
	mov	eax, [esi] # task flags
	and	eax, TASK_FLAG_RING_MASK
	shr	eax, TASK_FLAG_RING_SHIFT - 4	# eax = 16 * RPL = 2 selectors
	mov	ecx, eax
	shr	ecx, 4	# remember RPL
	add	eax, SEL_ring0CS
	test	dword ptr [esi], TASK_FLAG_FLATSEG # next esi=flags
	jz	1f
	add	eax, SEL_ring0CSf - SEL_ring0CS # use flat selectors
1:	or	al, cl	# add RPL
	stosd	# cs
	add	eax, 8	# data sel = code sel + 8

	mov	[ebx + task_regs + task_reg_ds], eax
	mov	[ebx + task_regs + task_reg_es], eax
	mov	[ebx + task_regs + task_reg_ss], eax

	pushfd	# need some eflags
	pop	eax
	or	eax, 1 << 9	# sti
	mov	dword ptr [ebx + task_regs + task_reg_eflags], eax

	lodsd	# task flags
	test	eax, ~(TASK_FLAG_TASK | TASK_FLAG_RING_MASK|TASK_FLAG_SUSPENDED|TASK_FLAG_FLATSEG)
	jnz	44f	# invalid bits

#		test eax, TASK_FLAG_SUSPENDED
#		jz 1f
#		or dword ptr [ebx + task_regs + task_reg_eflags], 1<<8 # Trap
#	1:
	# TODO: check if caller has permission to schedule CPL0 tasks
	or	eax, TASK_FLAG_SUSPENDED
	mov	[ebx + task_flags], eax

	lodsd	# task tabel
	mov	[ebx + task_label], eax
	mov	eax, [ebp + task_reg_eip]	# method return, conveniently
	mov	[ebx + task_registrar], eax
	mov	eax, [pid_counter]
	inc	dword ptr [pid_counter]
	mov	[ebx + task_pid], eax

	.if SCHEDULE_JOBS == 0
	# jobs disabled, alloc stack always
	or	dword ptr [ebx + task_flags], TASK_FLAG_TASK
	.else
	test	dword ptr [ebx + task_flags], TASK_FLAG_TASK
	jz	7f	# a job - don't allocate stack
	.endif

	call	task_setup_stack$	# out: ebp = task stack
	jc	66f	# malloc fail

	mov	eax, [ebx + task_pid]
	mov	[ebp + task_reg_eax], eax

	# enable the task, unless input flag says to keep it suspended
	test	dword ptr [esp + 5*4+32+12], TASK_FLAG_SUSPENDED
	jnz	1f
	and	dword ptr [ebx + task_flags], ~TASK_FLAG_SUSPENDED
1:

	clc
########
7:	SEM_UNLOCK [task_queue_sem]	# doesn't use flags

9:	popd	gs
	popd	fs
	popd	es
	popd	ds
	popd	ss
	popad

	.if 0
	pushf
	push	esi
	mov	esi, [esp + 8 + 16]
	call	print
	println " scheduled"
	pop	esi
	popf
	.endif

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
	DEBUG "task: "
	pushd	[esp + 16]
	call	_s_print
	DEBUG " addr: "
	push	edx
	mov	edx, [esp + 4+4]
	call	printhex8
	call	printspace
	call	debug_printsymbol
	pop	edx
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

55:	call	0f
	printlnc_ 4, "can't allocate paging structure"
	stc
	jmp	7b

44:	call	0f
	printc_ 4, "invalid task flags: "
	push	eax
	call	_s_printhex8
	call	newline
	int3
	stc
	jmp	7b

0:	printc_ 4, "schedule_task: "
	ret


task_setup_stack$:
	# check if the entry already has a stack
	mov	eax, [ebx + task_stackbuf]
	or	eax, eax
	jnz	1f
	# allocate a stack
	mov	eax, JOB_STACK_SIZE
	call	mallocz
	jc	9f	# continues to 66b
	mov	[ebx + task_stackbuf], eax
1:

	.if SCHEDULE_CLEAN_STACK
	push	eax
	mov	edi, eax
	mov	ecx, JOB_STACK_SIZE / 4
	xor	eax, eax
	rep	stosd
	pop	eax
	.endif

	add	eax, JOB_STACK_SIZE
	and	eax, ~0xf

	# prepare stack
	.if SCHEDULE_JOBS == 0
	sub	eax, 8
	# if edx is changed above:
	# mov edx, ebx
	# sub edx, [task_queue]
	mov	[eax + 4], edx	# set task index
	mov	[eax], dword ptr offset task_done
	test	dword ptr [ebx + task_flags], TASK_FLAG_FLATSEG
	jz	1f
	GDT_GET_BASE edx, cs
	add	[eax], edx	# correct for flat offset
1:
	.endif

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

	# if the task is not CPL0, fill in ss,esp on stack
	test	dword ptr [ebx + task_flags], TASK_FLAG_RING_MASK
	jz	1f
	push	eax
	lea	eax, [edi + 8]
	stosd
	mov	eax, edx
	stosd
	pop	eax
1:
	add	eax, TASK_REG_SIZE - 12

	mov	[ebx + task_regs + task_reg_esp], eax
	mov	[ebx + task_regs + task_reg_ss], edx # ss

	# if the task is not CPL0, allocate a CPL0 stack
	# (can be optimized but done separately for clarity)
	test	dword ptr [ebx + task_flags], TASK_FLAG_RING_MASK
#	jz	1f
	call	alloc_task_priv_stack
	# TODO: jc / unregister task

	.if 1 # TASK_PRIV_STACK_ASSERT
		pushad
		sub	ebx, [task_queue]
		ARRAY_LOOP [task_queue], SCHEDULE_STRUCT_SIZE, edx, ecx, 9999f
		cmp	ecx, ebx
		jz	9991f 
		cmp	[edx + ecx + task_flags], dword ptr -1
		jz	9991f
		cmp	eax, [edx + ecx + task_stack0_top]
		jnz	9991f
		printc 12, "ERROR: task duplicate privstack alloc: "
		DEBUG_DWORD eax
		DEBUG_DWORD ecx
		DEBUG_DWORD ebx
		DEBUGS [edx + ecx + task_label], "prior:"
		DEBUGS [edx + ebx + task_label], "cur"
		call newline
		int 3
	9991:
		ARRAY_ENDL
	9999:
		popad
	.endif

	mov	[ebx + task_stack0_top], eax
	mov	edx, eax
	sub	eax, 4096 >> offset TASK_PRIV_STACK_SHIFT
	and	eax, ~4095
	mov	esi, [ebx + task_cr3]
	call	paging_idmap_page
	GDT_GET_BASE eax, ss
	sub	edx, eax
	mov	[ebx + task_stack_esp0], edx
1:
	clc
9:	ret


KAPI_DECLARE schedule_task_setopt
# in: eax = pid
# in: ebx = option ID
# in: edx = option value
schedule_task_setopt:
	push_	ebx edx ecx esi
	mov	esi, ebx	# backup option id
	mov	ecx, edx	# backup option value
	call	task_get_by_pid	#out: ebx + edx
	jc	91f

	cmp	esi, TASK_FLAG_OPT_DEV_PCI
	jnz	92f
	mov	[ebx + edx + task_irq_service_pci_class], ecx # TODO, WIP

0:	clc
0:	pop_	esi ecx edx ebx
	ret

92:	PUSH_TXT "unknown option"
	jmp	9f
91:	PUSH_TXT "unknown pid"
9:	printc 4, "schedule_task_setopt: "
	call	_s_println
	stc
	jmp	0b
############################################################################
# Task Privileged Stack Allocation
TASK_PRIV_STACK_DEBUG		= 0	# general messages
TASK_PRIV_STACK_ASSERT		= 1	# enable some integrity assertions
TASK_PRIV_STACK_DEBUG_STACK	= 0	# stack pointers
TASK_PRIV_STACK_DEBUG_BITS	= 0	# bit indices

.data SECTION_DATA_BSS
# Since the page size is a power of 2, having a whole number of stacks in
# a page requires dividing by a power of 2.
TASK_PRIV_STACK_SHIFT = 1
task_stack_free:	.long 0	# bit array; 1 indicates availability
task_stack_pages:	.long 0	# ptr array
.text32
# in: ebx = task descriptor
# modifies: ecx, edx, edi, esi
alloc_task_priv_stack:
	.if TASK_PRIV_STACK_DEBUG
		DEBUG "alloc task stack"
	.endif
	mov	edi, [task_stack_free]
	or	edi, edi
	jz	1f

	.if TASK_PRIV_STACK_DEBUG > 1
		mov	edx, [edi + array_index]
		shl	edx, 5-2
		DEBUG_DWORD edx,"max pages @ free"
	.endif
	.if TASK_PRIV_STACK_DEBUG_BITS
		mov	esi, edi
		mov	ecx, [edi + array_index]
		shr	ecx, 2
	0:	lodsd
		mov	edx, eax
		call	printhex8
		loop	0b
	.endif

	xor	eax, eax
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	mov	edx, ecx	# remember size
	repz	scasd	# find dword with at least 1 bit set
	jz	1f	# no free stacks

	bsf	eax, [edi - 4]	# jz can't happen
	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD [edi-4],"bitstring"
		DEBUG_DWORD eax,"bit"
	.endif
	btr	[edi - 4], eax	# clear bit - mark allocated
	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD [edi-4]
	.endif

	# carry should be set after btr; use it to dec edx
	sbb	edx, ecx	# edx = dword index

	.if TASK_PRIV_STACK_DEBUG_BITS
		# doublecheck
		sub	edi, 4
		sub	edi, [task_stack_free]
		shr	edi, 2
		DEBUG_DWORD edx, "bitflags index"
		cmp	edi, edx
		jz	22f
		printc 4, "bitflag index calculation error"
		DEBUG_DWORD edi # should match edx
		int 3
	22:
	.endif

	shl	edx, 5		# * 32 bits
	add	eax, edx	# eax = bit index
	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD eax,"bitindex"
	.endif
	mov	[ebx + task_stack0_bitindex], eax

	# convert bit index to page + stack_offset_in_page
	mov	edx, eax
	and	edx, (1<<TASK_PRIV_STACK_SHIFT)-1	# stack_in_page idx
	shr	eax, TASK_PRIV_STACK_SHIFT		# page index

	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD eax,"page index"
		DEBUG_DWORD edx,"S_I_P index", 0xf0
	.endif

	shl	edx, 12-TASK_PRIV_STACK_SHIFT		# stack_in_page offset
	mov	ecx, [task_stack_pages]
	mov	eax, [ecx + eax * 4]	# get the page pointer
	# eax = page; edx = offset in page (stack bottom)
	.if TASK_PRIV_STACK_DEBUG_STACK
		DEBUG_DWORD eax,"page ptr"
		DEBUG_DWORD edx, "stack offset"
	.endif
	lea	eax, [eax + edx + (4096>>TASK_PRIV_STACK_SHIFT)]	# stack top
	.if TASK_PRIV_STACK_DEBUG
		DEBUG_DWORD eax,"stack"
	.endif
	ret
########

	# get bit index from base
	#
	# index =   ptr / 32
	# bit   = ( ptr / 32 ) * 4
	#
	.macro DWORD_PTR_TO_BITARRAY_PTR index, bit, dptr
.ifnc \dptr,\index;	mov     \index, \dptr    ; .endif
.ifnc \dptr,\bit;	mov     \bit, \dptr      ; .endif
			shr     \index, 5-2
			shr	\bit, 2
			and     \index, ~3
			and     \bit, 31
	.endm


1:	# no free stack; allocate.
	.if TASK_PRIV_STACK_DEBUG
		DEBUG "allocating stackpage"
	.endif

	PTR_ARRAY_NEWENTRY [task_stack_pages], 32, 91f
	mov	edi, eax

	.if TASK_PRIV_STACK_DEBUG > 1
		DEBUG_DWORD [edi + array_index]
		DEBUG_DWORD edx
	.endif

	mov	esi, cr3
	mov	esi, [page_directory_phys]
	call	paging_alloc_page_idmap
	jc	9f

	mov	[edi + edx], eax
	lea	ecx, [eax + 4096 >> TASK_PRIV_STACK_SHIFT] # stack top

	.if TASK_PRIV_STACK_DEBUG_STACK
		DEBUG_DWORD eax,"stackpage"
		DEBUG_DWORD ecx, "stack top"
		DEBUG_DWORD edx,"dptr"
	.endif

	shr	edx, 2	# dword index
	shl	edx, TASK_PRIV_STACK_SHIFT	# stack index

	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD edx, "stack index"
	.endif

	mov	[ebx + task_stack0_bitindex], edx
	#DWORD_PTR_TO_BITARRAY_PTR index=edx, bit=edi, dptr=edx

	mov	edi, edx
	shr	edx, 5
	and	edi, 31

	# pretty much redundant
	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD edx,"idx"
		DEBUG_DWORD edi,"bit"
		mov	eax, edx
		shl	eax, 5
		add	eax, edi
		DEBUG_DWORD eax,"bitindex"
		cmp	[ebx + task_stack0_bitindex], eax
		jz	22f
		printc 4, "bitindex calculation error"
		int 3
	22:
	.endif

	mov	eax, [task_stack_free]
	or	eax, eax
	jz	2f
	cmp	edx, [eax + array_index]
	jb	1f
2:	PTR_ARRAY_NEWENTRY [task_stack_free], 4, 91f
	# mark all stacks in the page as free
	mov	[eax + edx], dword ptr (1<<TASK_PRIV_STACK_SHIFT)-1
	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD [eax+edx]
	.endif
1:	btr	[eax + edx], edi	# clear bit - mark allocated
	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD [eax+edx]
	.endif
	mov	eax, ecx
	ret

91:	printlnc 4, "alloc_task_priv_stack: cannot allocate array"
	stc
	ret
9:	printlnc 4, "alloc_task_priv_stack: no more pages"
	stc
	ret

# in: eax = task_esp0
# in: ebx = task descriptor
free_task_priv_stack:
	push_	esi edi edx
	.if TASK_PRIV_STACK_DEBUG
		DEBUG "free_task_priv_stack"
		mov	esi, [ebx + task_label]
		call	print
		DEBUG_DWORD eax, "stack top"
	.endif

	sub	eax, 4096 >> TASK_PRIV_STACK_SHIFT	# get base
	.if TASK_PRIV_STACK_DEBUG_STACK
		DEBUG_DWORD eax,"stack base"
	.endif
	mov	edx, eax
	and	eax, ~4095			# page-align
	.if TASK_PRIV_STACK_DEBUG_STACK
		DEBUG_DWORD eax,"page"
	.endif
	and	edx, 4095			# stack_in_page offset
	.if TASK_PRIV_STACK_DEBUG_STACK
		DEBUG_DWORD edx,"stack offs"
	.endif
	shr	edx, 12-TASK_PRIV_STACK_SHIFT	# stack_in_page index

	mov	edi, [task_stack_pages]
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	mov	esi, ecx
	repnz	scasd				# find page
	jnz	9f
	sub	esi, ecx			# page index + 1
	dec	esi

	# esi = page index
	# edx = stack_in_page index
	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD esi, "page index"
		DEBUG_DWORD edx, "stack_in_page idx"
	.endif
	# convert to bit index.
	shl	esi, TASK_PRIV_STACK_SHIFT
	or	edx, esi
	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD edx,"stack index"
	.endif
	.if TASK_PRIV_STACK_ASSERT
		cmp	edx, [ebx + task_stack0_bitindex]
		jz	1f
		printc 4, "bitindex mismatch: ";
		DEBUG_DWORD [ebx + task_stack0_bitindex]; DEBUG_DWORD edx
		int 3
	1:
	.endif

	mov	edi, [task_stack_free]
	# split the bitindex into 32-bit base/index
	mov	eax, edx
	shr	eax, 5		# dword index
	and	edx, 31		# bit index
	.if TASK_PRIV_STACK_DEBUG_BITS
		DEBUG_DWORD eax,"bitstring dword idx"
		DEBUG_DWORD edx, "bit"
	.endif
	bts	[edi + eax * 4], edx	# set bit - mark free

0:	pop_	edx edi esi
	ret
9:	printc 4, "free_tasks_priv_stack: unknown page: "
	DEBUG_DWORD edx

	int 3
	jmp	0b


####################################
# in: eax = pid
# out: ebx + ecx
task_get_by_pid:
	ARRAY_LOOP [task_queue], SCHEDULE_STRUCT_SIZE, ebx, ecx, 9f
	cmp	eax, [ebx + ecx + task_pid]
	jz	1f
	ARRAY_ENDL
	stc
1:	ret

# in: eax = pid
task_suspend:
	push	ebx
	push	ecx
	call	task_get_by_pid
	jc	9f
	or	dword ptr [ebx + ecx + task_flags], TASK_FLAG_SUSPENDED
9:	pop	ecx
	pop	ebx
	ret

# in: eax = pid
task_resume:
	push	ebx
	push	ecx
	call	task_get_by_pid
	jc	9f
	and	dword ptr [ebx + ecx + task_flags], ~TASK_FLAG_SUSPENDED
9:	pop	ecx
	pop	ebx
	ret

# in: ebx = task descriptor
task_setup_paging:
	push_	edx ebx esi edi ecx ebp
	mov	ebp, ebx

	# a task may be scheduled from a task not the kernel task.
	# get the active page directory to operate upon, as we want
	# the pages accessible in the current context.
	# UPDATE: this code runs in the kernel context.
	mov	esi, cr3

	call	paging_alloc_page_idmap
	jc	9f
	mov	[ebp + task_page_dir], eax	# PDE, aka task_cr3
	mov	[ebp + task_cur_cr3], eax	# PDE

	call	paging_alloc_page_idmap
	jc	91f
	mov	[ebp + task_page_tab_lo], eax	# PT 0

	call	paging_alloc_page_idmap
	jc	92f
	mov	[ebp + task_page_tab_hi], eax	# PT hi

	###########

	GDT_GET_BASE edx, ds

	sub	esi, edx

	# copy the PTE for the low 4mb. It is assumed that this method is
	# called from a task that has the low 4Mb identity mapped, and the PT
	# for it readable.  This method ensures that tasks created by it
	# conform to these assumptions.
	# This method further ensures that any new task will receive a copy of
	# the PT for low memory from it's _calling_ task, thus propagating any
	# restrictions (since the original kernel PD is fully mapped).
	mov	esi, [esi]	# PDE/PT for low 4mb
	mov	ecx, 1024
	and	esi, 0xfffff000	# mask out flags
	mov	edi, [ebp + task_page_tab_lo]
	sub	esi, edx	# make ds-relative
	sub	edi, edx	# make ds-relative
.if 1	# mask active and dirty flags to track task page access
0:	lodsd
	and	eax, ~(PTE_FLAG_A|PTE_FLAG_D)
or	ax, PTE_FLAG_U|PTE_FLAG_RW
	stosd
	loop	0b
.else
	rep	movsd
.endif

	# map the page tables
	mov	esi, [ebp + task_page_dir]
	sub	esi, edx

	# map the low PT (0..4mb region)
	mov	eax, [ebp + task_page_tab_lo]
	or	eax, PDE_FLAG_P | PDE_FLAG_RW ##| PDE_FLAG_U # allow userlevel access (task user stack)
	mov	[esi], eax	# map low 4mb

#######################################################
# This section is only needed if new task creation should be enabled
# for the task being created.

	#####################################
	# create a PDE: map a page table.
	#
	# This will be used if new tasks are scheduled from the one being setup
	mov	eax, [ebp + task_page_tab_hi]
	# map the PT, so that pages in the page_tab_hi range can be mapped
	# after allocation, such as creating a new task.
	mov	ecx, eax	# ASSUMPTION: page_dir, page_tab_(lo|hi) are
	shr	ecx, 22		# in the same 4Mb.
	or	eax, PDE_FLAG_P | PDE_FLAG_RW #  no RW = kb fail
	mov	[esi + ecx * 4], eax	# register mapping for hi

	###################################################
	# make page tables accessible: identity map them.
	#
	add	esi, edx
	# mapped because it is copied for new tasks
	mov	eax, [ebp + task_page_dir]
	or	ax, PTE_FLAG_P | PTE_FLAG_U  	# page-dir read-only
	call	paging_idmap_page_f
	# idem
	mov	eax, [ebp + task_page_tab_lo]
	or	ax, PTE_FLAG_P			# page-table read-only
or ax, PTE_FLAG_U|PTE_FLAG_RW
	call	paging_idmap_page_f
	# mapped because allocating new pages requires write access to map them
	mov	eax, [ebp + task_page_tab_hi]
	or	ax, PTE_FLAG_P | PTE_FLAG_RW	# high pages RW
	call	paging_idmap_page_f
#######################################################

	#


	clc

9:	pop_	ebp ecx edi esi ebx edx
	ret

92:	mov	eax, [ebx + task_page_tab_lo]
	call	mfree_page_phys
91:	mov	eax, [ebx + task_page_tab_hi]
	call	mfree_page_phys
	stc
	jmp	9b

	clc
9:	pop	ebx
	ret

# stores the page as a PTE in the PD
# in: ebx= task ptr
# in: eax= page address
# in: edx = address to map it to
task_map_pde:
	push	ecx
	mov	ecx, cr3
	push	ecx
	mov	ecx, [page_directory_phys]
	mov	cr3, ecx

	test	edx, ((1<<22)-1)
	jnz	9f
	push	edx
	shr	edx,22
	shl	edx, 2
	add	edx, [ebx + task_page_dir]
#	invlpg	[edx]
	GDT_GET_BASE ecx, ds
	sub	edx, ecx
	mov	[edx], eax
	pop	edx
#	invlpg	[edx]

	clc
0:
	pop	ecx
	mov	cr3, ecx
	pop	ecx
	ret
9:	printlnc 4, "task_map_pde: not 4Mb boundary/flags"
	int 3
	stc
	jmp	0b
##############################################################################

# in: [esp+4] = timeout in ms (0=indefinitely)
# in: [esp+0] = address of mutex
# Callee frees stack.
# NOTE: this accesses the task structure, which should become hidden to tasks.
KAPI_DECLARE task_wait_io, 2
task_wait_io:
	push_	eax ecx ebp
	lea	ebp, [esp + 3*4 + 4]
	SEM_SPINLOCK [task_queue_sem]	# destroys eax, ecx
	mov	eax, [scheduler_current_task_idx]
	add	eax, [task_queue]

	mov	ecx, [ebp]
	mov	[eax + task_io_sem_ptr], ecx
	# timeout
	mov	ecx, [ebp+4]
	cmp	ecx, -1
	jz	1f
		#
		cmp	ecx, 0xffff0000
		jb 2f
			DEBUG_DWORD ecx, "timeout large", 0xb
		2:
		#
	add	ecx, [clock_ms]
1:	mov	[eax + task_io_sem_timeout], ecx	# store 'abs' time

	or	[eax + task_flags], dword ptr TASK_FLAG_WAIT_IO #|TASK_FLAG_SUSPENDED

	pop_	ebp ecx eax
	SEM_UNLOCK [task_queue_sem]

	#YIELD # does another kapi call
	call	schedule_near
	ret	8


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

# in: ebp = task
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

	PUSHSTRING "top"
	mov	esi, esp
	call	cmd_tasks
	add	esp, 4

	POP_SCREENPOS
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret

#############################################################################
# local utility method to call 'cmd_tasks' as 'ps'
cmd_ps$:
	pushd	0	# end of commandline
	PUSHSTRING "ps"
	mov	esi, esp
	call	cmd_tasks
	add	esp, 4
	ret

# 'ps' command, serving double duty as 'top' depending on how it is called.
cmd_tasks:
	SEM_SPINLOCK [task_queue_sem]
	push	ebp
	mov	ebp, [esi]

	# check for 'ps -p PID'
	cmp	dword ptr [ebp], 't'|('o'<<8)|('p'<<16)
	jz	1f		# not 'ps'
	cmpd	[esi + 4], 0	# check if there is an argument
	jz	1f		# no argument
	call	cmd_get_task$	# in: esi=cmdline; out: eax=pid,ebx+ecx=task
	jc	0f		# error printed, done
	mov	edi, ecx	# backup task index
	mov	eax, ebx	# task_print expects eax + ebx
	mov	ebx, ecx
	call	task_print$
	# let's print some more detailed info:
	add	ebx, eax	# consolidate pointer

	mov	edx, [ebx + task_stack_ss]
	print "usr stack: "
	call	printhex4
	print ":"
	mov	edx, [ebx + task_stack_esp]
	call	printhex8
	call	newline

	mov	edx, [ebx + task_stack_ss0]
	print "sys stack: "
	call	printhex4
	print ":"
	mov	edx, [ebx + task_stack_esp0]
	call	printhex8
	call	newline

	mov	edx, [ebx + task_regs + task_reg_cs]
	print "cs:eip: "
	call	printhex4
	print ":"
	mov	edx, [ebx + task_regs + task_reg_eip]
	call	printhex8
	call	newline

	mov	eax, edi	# get task index
	call	task_print_stack$

	jmp	0f		# done



1:	pushcolor TASK_PRINT_BG_COLOR | 7
	print "Tasks: "
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
	print " sched idx: "
	mov	eax, [task_index]
	xor	edx, edx
	div	ebx
	call	printdec32
.endif
.endif
	print " Uptime: "
	call	get_time_ms_40_24
	call	print_time_ms_40_24
	call	newline

	call	task_print_h$

	xor	ecx, ecx # index counter, saves dividing ebx by SCHED_STR_SIZE
	ARRAY_LOOP [task_queue], SCHEDULE_STRUCT_SIZE, eax, ebx, 9f
	.if TASK_PRINT_DEAD_JOBS == 0	# default, to keep an eye on array reuse
	cmp	[eax + ebx + task_flags], dword ptr -1
	jz	3f
	.endif
	mov	edx, ecx
1:	color	TASK_PRINT_BG_COLOR | 7

	cmp	ebx, [scheduler_current_task_idx]
	jnz	1f
	color	TASK_PRINT_BG_COLOR | 15
	jmp	2f

1:	cmp	[eax + ebx + task_flags], dword ptr -1
	jnz	2f
	color	TASK_PRINT_BG_COLOR | 8

2:	call	task_print$
3:	inc	ecx
		# if called as 'top', dont print all
		cmp	dword ptr [ebp], 't'|('o'<<8)|('p'<<16)
		jnz	1f
		cmp	ecx, 20
		ja	9f
	1:
	ARRAY_ENDL
9:	popcolor
0:	pop	ebp
	SEM_UNLOCK [task_queue_sem]
	ret


task_print_h$:
.section .strings # a little kludge to keep the string from wrapping
200:
.ascii "idx pid P addr.... stack... flags... "
.if TASK_PRINT_2
.if TASK_PRINT_TLS;	.ascii "tls..... "; .else; .ascii "registrr "; .endif
.if TASK_PRINT_PARENT;	.ascii "parent.. "; .else; .ascii "eflags.. "; .endif
.asciz "label, symbol"
.else
.asciz "label... symbol"
.endif
.text32
	push	eax
	push	esi
	mov	ah, TASK_PRINT_BG_COLOR | 11
	mov	esi, offset 200b
	call	printlnc
	pop	esi
	pop	eax
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
# print current CPL (usually scheduler's CPL (0) on blocking IO)
	mov	edx, [eax + ebx + task_regs + task_reg_cs]
	and	dl, 3
	call	printhex1
	call	printspace
# print stack pointer
	mov	edx, [eax + ebx + task_regs + task_reg_eip]
mov edx, [eax + ebx + task_stack0_top]
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
	PRINTFLAG edx, TASK_FLAG_WAIT_IO,	"W", " "
	PRINTFLAG edx, TASK_FLAG_RESCHEDULE,	"r", " "	# XXX this is not a live flag
	PRINTFLAG edx, TASK_FLAG_TASK,		"T", "J"
	and	edx, TASK_FLAG_RING_MASK
	shr	edx, TASK_FLAG_RING_SHIFT
	call	printhex1	# CPL

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
		mov	edx, [eax + ebx + task_parent]
		mov	edx, [eax + edx + task_pid]
		call 	printhex8
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

	.if 1
#		DEBUG_WORD [eax+ebx + task_tsc_stop],"v"
#		DEBUG_DWORD [eax+ebx + task_tsc_stop+4],"v"
#		DEBUG_WORD [eax+ebx + task_tsc],"^"
#		DEBUG_DWORD [eax+ebx + task_tsc+4],"^"
		push	eax
		mov	edx, [eax + ebx + task_time]
		mov	eax, [eax + ebx + task_time+4]
#		shld	edx, eax, 8
#		shl	eax, 8
		push	edi
		sub	esp, 32
		mov	edi, esp
		call	sprint_time_ms_40_24
		movw	[edi], ' '
		sub	edi, esp

		push	ecx
		mov	ecx, 9
		sub	ecx, edi
		jle	11f
	10:	call	printspace
		loop	10b
	11:	pop	ecx

		push	esp
		call	_s_print
		add	esp, 32
		pop	edi
		pop	eax
	.elseif 0
		push_ eax ebx
		#call	printdec32
		xor	eax, eax
		shrd	eax, edx, 16
		mov bl, 6
		call	print_fixedpoint_32_32$
		pop_ ebx eax

#		DEBUG_DWORD [eax+ebx+task_tsc],"+"
#		DEBUG_DWORD [eax+ebx+task_tsc_stop],"-"
		mov edx, [eax+ebx+task_tsc]
		sub edx, [eax+ebx+task_tsc_stop]
		DEBUG_DWORD edx
	.else
		mov edx, [eax + ebx + task_time+4]
		call	printhex8
		mov edx, [eax + ebx + task_time]
		call	printhex8
	.endif


	.if 0
	mov	edx, [eax + ebx + task_schedcount]
	pushcolor 0x3
	call	printdec32
	popcolor
	.endif

	mov	edx, [eax + ebx + task_regs + task_reg_eip]
	call debug_printsymbol_short
	call newline

	popad
	ret

3:	call	printhex4	# meaningful relative offsets are usually < 64k
	jmp	2b

#############################################################################
cmd_top:
	mov	al, [schedule_show$]
	push	eax
	call	cls
	mov	byte ptr [schedule_show$], 3

0:	xor	ax, ax
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
	call	cmd_get_task$
	jc	9f	# errormsg already printed
	printc 11, "killing pid "
	mov	edx, [ebx + ecx + task_pid]
	call	printhex8
	printc 11, " '"
	mov	esi, [ebx + ecx + task_label]
	call	print
	printlnc 11, "'"
	or	[ebx + ecx + task_flags], dword ptr TASK_FLAG_DONE
9:	ret

cmd_suspend:
	call	cmd_get_task$
	jc	9f
	call	task_suspend
9:	ret

cmd_resume:
	call	cmd_get_task$
	jc	9f
	call	task_resume
9:	ret

# in: esi = commandline
# out: ebx + ecx = task structure ptr
# out: eax = pid
# NOTE! no semlocks!
cmd_get_task$:
	lodsd
	mov	edi, eax	# for errormsg
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

	call	task_get_by_pid
	jc	7f
	jmp	2f

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
	mov	eax, [ebx + ecx + task_pid]

2:	clc
	ret

7:	printlnc 4, "no such task"
	stc
	ret
8:	printlnc 4, "cannot lock task queue"
	stc
	ret
9:	printc 12, "usage: "
	mov	esi, edi
	call	print
	printlnc 12, " [-i <idx> | -p <hex pid>]"
	stc
	ret
.endif
