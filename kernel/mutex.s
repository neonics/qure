###############################################################################
# Semaphores and Mutexes
#
.intel_syntax noprefix


################################################################
# Mutex - mutual exclusion
#
.data SECTION_DATA_SEMAPHORES
.align 4
mutex:		.long 0 # -1	# 32 mutexes, initially unlocked #locked.
	MUTEX_SCHEDULER	= 1
#	MUTEX_SCREEN	= 2
	MUTEX_KB	= 4
	MUTEX_NET	= 8
	MUTEX_TCP_CONN	= 16


.text32

# out: CF = 1: fail, mutex was already locked.
.macro MUTEX_LOCK name, nolocklabel=0, locklabel=0, debug=0
	lock bts dword ptr [mutex], MUTEX_\name
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
	.if \debug
		jc	100f
		printc 4, "MUTEX_UNLOCK \name: unlock error"
		clc
	100:
	.endif
.endm


.macro MUTEX_SPINLOCK name, nolocklabel=0, locklabel=0, debug=0
	push	ecx
	mov	ecx, 1000
101:	MUTEX_LOCK \name, locklabel=102f
	hlt
	loop	101b
102:	pop	ecx
	.ifnc 0,\locklabel
	jnc	\locklabel
	.endif
	.if \debug
	printc 5, "MUTEX_SPINLOCK \name: fail"
	stc
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


.macro SEM_UNLOCK sem
	mov	dword ptr \sem, 0
.endm




