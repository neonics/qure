###############################################################################
# Semaphores and Mutexes
#
.intel_syntax noprefix

MUTEX_DEBUG = 1	# registers lock owners

################################################################
# Mutex - mutual exclusion
#
.data SECTION_DATA_SEMAPHORES
.align 4
mutex:		.long 0 # -1	# 32 mutexes, initially unlocked #locked.
	MUTEX_SCHEDULER	= 0
#	MUTEX_SCREEN	= 1
	MUTEX_KB	= 2
	MUTEX_NET	= 3
	MUTEX_TCP_CONN	= 4
	MUTEX_SOCK	= 5

	NUM_MUTEXES	= 6

mutex_owner:	.space 4 * NUM_MUTEXES

mutex_names:
mutex_name_SCHEDULER:	.asciz "SCHEDULER"
mutex_name_SCREEN:	.asciz "SCREEN"
mutex_name_KB:		.asciz "KB"
mutex_name_NET:		.asciz "NET"
mutex_name_TCP_CONN:	.asciz "TCP_CONN"
mutex_name_SOCK:	.asciz "SOCK"
.text32

.macro YIELD
	.if 1
		call	schedule_near
		hlt
	.else
		pushf
		sti
		hlt
		popf
	.endif
.endm

# out: CF = 1: fail, mutex was already locked.
.macro MUTEX_LOCK name, nolocklabel=0, locklabel=0, debug=0
	lock bts dword ptr [mutex], MUTEX_\name

	.if MUTEX_DEBUG
		jc	100f
		call	101f
	101:	pop	[mutex_owner + MUTEX_\name * 4]
	100:
	.endif

	.if \debug
		jnc	100f
		printc 5, "MUTEX LOCK \name: fail"
		stc
	100:	
	.endif
	.ifnc 0,\nolocklabel
	jc	\nolocklabel
	.endif
	.ifnc 0,\locklabel
	jnc	\locklabel
	.endif
.endm

# out: CF = 1: it was locked (ok); 0: another thread unlocked it (err)
.macro MUTEX_UNLOCK name, debug=0
	lock btr dword ptr [mutex], MUTEX_\name

	.if MUTEX_DEBUG > 1
		mov	[mutex_owner + MUTEX_\name * 4], dword ptr 0
	.endif

	.if \debug
		jc	100f
		printc 4, "MUTEX_UNLOCK \name: unlock error"
		clc
	100:
	.endif
.endm


.macro MUTEX_SPINLOCK_ name
1999:	lock bts dword ptr [mutex], MUTEX_\name
	jc	1999b
	call	1999f
1999:	pop	dword ptr [mutex_owner + MUTEX_\name * 4]
.endm

.macro MUTEX_UNLOCK_ name
	pushf
	lock btr dword ptr [mutex], MUTEX_\name
	mov	dword ptr [mutex_owner + MUTEX_\name * 4], 0
	popf
.endm

.macro MUTEX_SCHEDLOCK name
1999:	lock bts dword ptr [mutex], MUTEX_\name
	jnc	1999f
	call	schedule_near
	jmp	1999b
1999:	call	1999f
1999:	pop	dword ptr [mutex_owner + MUTEX_\name * 4]
.endm

.macro MUTEX_SPINLOCK name, nolocklabel=0, locklabel=0, debug=0
	push	ecx
	mov	ecx, 10
101:	MUTEX_LOCK \name, locklabel=102f
	YIELD
	loop	101b
	.if \debug
		printc 5, "MUTEX_SPINLOCK \name: fail"
		.if MUTEX_DEBUG > 1
			print " owner: "
			push edx
			mov edx,	dword ptr [mutex_owner + MUTEX_\name * 4]
			call printhex8
			call newline
			print "MUTEX: "
			mov edx, [mutex]
			call printbin8
			call printspace
			pop edx
		.endif
	.endif
	stc
102:	pop	ecx
	.ifnc 0,\locklabel
	jnc	\locklabel
	.endif
	.ifnc 0,\nolocklabel
	jc	\nolocklabel
	.endif
.endm


#####################################################################
# Semaphores (shared variable)
#

# Semaphore/mutex relevant mnemonics:
# lock, cmpxchg, xadd, mov, inc, dec, adc, sbb, bt, bts, btc, btr, not, neg, or, and

# A fail-fast semaphore lock.
#
# This macro does a single check, leaving the semaphore in a locked state
# regardless of whether the lock succeeded.
# When the lock does not succeed, control is transferred to \nolocklabel.
# out: ZF = 1: have lock
# out: eax = 0 (have locK), other value: no lock.
.macro SEM_LOCK sem, nolocklabel=0
	.if INTEL_ARCHITECTURE > 4
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
# halting is the most efficient way to wait for a semaphore to become free
# besides triggering the scheduler.
#
# On an SMP system, potentially [pit_timer_interval] milliseconds are wasted,
# in the case where IRQ's are only executed by one CPU at a time,
# and where two or more CPU's are competing to register a task, where one
# has obtained a lock, and the other enters halt.
# I have not researched SMP implementation yet, thus, it is possible that even though
# any IRQ is only executed on a single CPU at a time, that two different IRQ's,
# such as the timer and the network, are executed simultaneously. In this case,
# since all IRQ's (except exceptions), are mapped to the scheduler, it is
# possible that the scheduler is called concurrently. However, the 'fail-fast'
# lock mechanism would take care of attempting any task switch.
#
# out: CF = ZF (1: no lock; 0: lock)
# destroys: eax, ecx
.macro SEM_SPINLOCK sem, locklabel=0, nolocklabel=0
	.ifc 0,\locklabel
	_LOCKLABEL = 109f
	.else
	_LOCKLABEL = \locklabel
	.endif

	mov	ecx, 0x1000
100:
	.if INTEL_ARCHITECTURE > 4
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

	YIELD
	loop	100b

	.ifc 0,\nolocklabel
		or	eax, eax
		stc
	.else
		jmp \nolocklabel
	.endif
109:
.endm


.macro SEM_UNLOCK sem
	mov	dword ptr \sem, 0
.endm




