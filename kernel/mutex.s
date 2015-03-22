###############################################################################
# Semaphores and Mutexes
#
.intel_syntax noprefix

MUTEX_DEBUG = 1	# registers lock owners
MUTEX_ASSERT = 3
# 0: no checks;
# 1: check & print mutex name and caller address
# 2: also print the mutexes and process list
# 3: and finally, invoke debugger

MUTEX_SPINLOCK_TIMEOUT=20	# number of yields; 0=no timeout.


.if DEFINE
################################################################
# Mutex - mutual exclusion
#
.global mutex
.global mutex_lock
.global mutex_spinlock
.global mutex_unlock


.data SECTION_DATA_SEMAPHORES
.align 4
mutex:		.long 0 # -1	# 32 mutexes, initially unlocked #locked.
.endif
	MUTEX_SCHEDULER	= 0
#	MUTEX_SCREEN	= 1
	MUTEX_MEM	= 2
	MUTEX_KB	= 3
	MUTEX_FS	= 4
	MUTEX_NET	= 5
	MUTEX_TCP_CONN	= 6
	MUTEX_SOCK	= 7
	MUTEX_TIME	= 8

	NUM_MUTEXES	= 9

.if DEFINE

.data SECTION_DATA_BSS
mutex_owner:	.space 4 * NUM_MUTEXES
mutex_released:	.space 4 * NUM_MUTEXES
mutex_lock_time:.space 4 * NUM_MUTEXES
mutex_unlock_time:.space 4 * NUM_MUTEXES
mutex_lock_task:.space 4 * NUM_MUTEXES
mutex_unlock_task:.space 4 * NUM_MUTEXES
mutex_seq:	.long 0
mutex_lock_seq:	.space 4 * NUM_MUTEXES
mutex_unlock_seq:.space 4 * NUM_MUTEXES

.data
mutex_names:
STRINGPTR "SCHEDULER"
STRINGPTR "SCREEN"
STRINGPTR "MEM"
STRINGPTR "KB"
STRINGPTR "FS"
STRINGPTR "NET"
STRINGPTR "TCP_CONN"
STRINGPTR "SOCK"
STRINGPTR "TIME"


.text32

# in: [esp] = MUTEX_\name bit number
mutex_lock:
	push	eax
	mov	eax, [esp + 8]
	lock bts dword ptr [mutex], eax

.if MUTEX_ASSERT
	jnc	1f
	call	mutex_fail$
	STACKTRACE 4, 0	# 4: eax
1:
.endif

.if MUTEX_DEBUG
	pop	eax
	jmp	mutex_record_lock$
.else
	pop	eax
	ret	4
.endif



# in: [esp] = MUTEX_\name bit number
mutex_spinlock:
	push	eax
	mov	eax, [esp + 8]
.if MUTEX_SPINLOCK_TIMEOUT
	push	ecx
	mov	ecx, MUTEX_SPINLOCK_TIMEOUT
.endif
	jmp	1f

.if MUTEX_SPINLOCK_TIMEOUT
2:	call	mutex_fail$
	STACKTRACE 8, 0	# 8: eax, ecx
	mov	ecx, MUTEX_SPINLOCK_TIMEOUT
.endif

0:
.if MUTEX_SPINLOCK_TIMEOUT
	dec	ecx
	jz	2b
.endif
	YIELD

1:	lock bts dword ptr [mutex], eax
	jc	0b
.if MUTEX_SPINLOCK_TIMEOUT
	pop	ecx
.endif

.if MUTEX_DEBUG
	pop	eax
	jmp	mutex_record_lock$
.else
	pop	eax
	ret	4
.endif



# in: [esp] = MUTEX_\name
mutex_unlock:
	push	eax
	mov	eax, [esp + 8]	# mutex bit
	pushf

	lock btr dword ptr [mutex], eax

.if MUTEX_ASSERT
	jc	1f
	call	mutex_fail$
	STACKTRACE 4, 0
1:
.endif
	popf

.if MUTEX_DEBUG
	pop	eax
	jmp	mutex_record_unlock$
.else
	pop	eax
	ret	4
.endif

########################################################

# in: eax = MUTEX_\name bit
# in: CF according to btr/bts expectation
mutex_fail$:
	jc	1f
	printc 0x4f, "failed to release lock "
	jmp	2f
1:	printc 0x4f, "failed to acquire lock "
2:	pushd	[mutex_names + eax * 4]
	call	_s_println
	.if MUTEX_ASSERT > 1
		call	mutex_print
#		call	cmd_ps$
	.endif
	.if MUTEX_ASSERT > 2
		int 3
	.endif
	ret

# in: [esp] = MUTEX_\name * 4
mutex_record_lock$:
	push_	eax edx
	mov	eax, [esp + 12]	# MUTEX_\name * 4
	shl	eax, 2
	mov	edx, [esp + 8]	# call address
	mov	[mutex_owner + eax], edx
	mov	edx, [clock]
	mov	[mutex_lock_time + eax], edx
	mov	edx, [scheduler_current_task_idx]
	mov	[mutex_lock_task + eax], edx
	incd	[mutex_seq]
	mov	edx, [mutex_seq]
	mov	[mutex_lock_seq + eax], edx
	pop_	edx eax
	clc	# previous mutex value
	ret	4

mutex_record_unlock$:
	# for now just copy/paste code (could save some space here)
	pushf
	push_	eax edx
	mov	eax, [esp + 16]	# MUTEX_\name * 4
	shl	eax, 2	# smaller opcodes than eax * 4
	mov	edx, [esp + 12]	# call address
	mov	[mutex_released + eax], edx
	mov	edx, [clock]
	mov	[mutex_unlock_time + eax], edx
	mov	edx, [scheduler_current_task_idx]
	mov	[mutex_unlock_task + eax], edx
	incd	[mutex_seq]
	mov	edx, [mutex_seq]
	mov	[mutex_unlock_seq + eax], edx
	pop_	edx eax
	popf
	ret	4



################################################################
# Printing mutexes
.data SECTION_DATA_BSS
mutex_col_width$: .byte 0
.text32
mutex_calc_col_width$:
	# calculate mutex name width
	xor	edx, edx
	mov	ecx, NUM_MUTEXES
	mov	esi, offset mutex_names
0:	lodsd
	call	strlen
	cmp	eax, edx
	jb	1f
	mov	edx, eax
1:	loop	0b
	inc	edx
	mov	[mutex_col_width$], dl
	ret

mutex_print:
	push_	eax ebx ecx edx esi edi

	cmp	byte ptr [mutex_col_width$], 0
	jnz	1f
	call	mutex_calc_col_width$
1:

	mov	ecx, NUM_MUTEXES
	printc_ 11, "mutex: "
	mov	edx, [mutex]
	call	nprintbin
	printc_ 11, " current task: "
	pushd	[scheduler_current_task_idx]
	call	_s_printhex4
	call	newline
	mov	ebx, edx

	mov	esi, offset mutex_owner
	mov	edi, offset mutex_names
########
0:	mov	edx, NUM_MUTEXES
	sub	edx, ecx
	mov	eax, 1
	xchg	edx, ecx
	shl	eax, cl
	xchg	edx, ecx

	test	ebx, eax
	mov	ah, 7
	jz	3f
	mov	ah, 15
3:	pushcolor ah
	call	printdec32
	printchar_ ':'

	push	esi
	mov	esi, [mutex_names + edx * 4]
	push	ecx
	movzx	ecx, byte ptr [mutex_col_width$]
	add	ecx, esi
	call	print_
	sub	ecx, esi
	jbe	1f
2:	call	printspace
	loop	2b
1:	pop	ecx
	pop	esi
	popcolor

	printchar_ '='
	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace

	mov	eax, NUM_MUTEXES
	sub	eax, ecx
	mov	edx, [mutex_lock_time + eax * 4]
	call	printhex8
	call	printspace

	mov	edx, [mutex_lock_task + eax * 4]
	add	edx, [task_queue]
	mov	edx, [edx + task_pid]
	call	printhex4
	call	printspace
	mov	edx, [mutex_lock_seq + eax * 4]
	call	printhex8

	mov	edx, [esi - 4]
	or	edx, edx
	jz	1f
	call	printspace
	call	debug_printsymbol_short
1:	call	newline

	# print release
	push	ecx
	movzx	ecx, byte ptr [mutex_col_width$]
	add	ecx, 2
2:	call	printspace
	loop	2b
	pop	ecx
	mov	eax, NUM_MUTEXES
	sub	eax, ecx
	mov	edx, [mutex_released + eax * 4]
	call	printhex8
	call	printspace
	mov	edx, [mutex_unlock_time + eax * 4]
	call	printhex8
	call	printspace

	mov	edx, [mutex_unlock_task + eax * 4]
	add	edx, [task_queue]
	mov	edx, [edx + task_pid]
	call	printhex4
	call	printspace
	mov	edx, [mutex_unlock_seq + eax * 4]
	call	printhex8
	call	printspace
	mov	edx, [mutex_released + eax * 4]
	or	edx, edx
	jz	1f
	call	debug_printsymbol_short
1:	call	newline

	dec	ecx
	jnz	0b
#	loop	0b
########
	pop_	edi esi edx ecx ebx eax
	ret

################################################################




.endif

.ifndef __MUTEX_DECLARE
__MUTEX_DECLARE = 1

.macro YIELD timeout=0
	.ifnc \timeout,0
	YIELD_SEM 0, \timeout	# no sem ptr
	.else
	KAPI_CALL yield
	.endif
.endm



# out: CF = 1: fail, mutex was already locked.
.macro MUTEX_LOCK name, nolocklabel=0, locklabel=0
	pushd	MUTEX_\name
	call	mutex_lock
	.ifnc 0,\nolocklabel
	jc	\nolocklabel
	.endif
	.ifnc 0,\locklabel
	jnc	\locklabel
	.endif
.endm

.macro MUTEX_UNLOCK name
	pushd	MUTEX_\name
	call	mutex_unlock
.endm

.macro MUTEX_SPINLOCK name
	pushd	MUTEX_\name
	call	mutex_spinlock
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



################################################################################
# Read/Write Locking
#

################################################################################
# Jcc breakdown:
#
# SZCO | G GE NG NGE L LE NL NLE A AE NA NAE BE NBE |
# ---- | ------------------------------------------ |---------------------------
#      | G GE             NL NLE A AE           NBE |INC DEC ADD SUB            
#   C  | G GE             NL NLE      NA NAE BE     |                SUB-1 ADD-1
#  Z   |   GE NG       LE NL       AE NA     BE	    |INC DEC     SUB SUB-1 
#  ZC  |   GE NG       LE NL          NA NAE BE	    |        ADD           ADD-1
# S    |      NG NGE L LE        A AE           NBE |INC DEC ADD SUB       ADD-1
# S C  |      NG NGE L LE             NA NAE BE     |                SUB-1 ADD-1
# S  O | G GE             NL NLE A AE           NBE | add 7fffffff
#    O |      NG NGE L LE        A AE           NBE | sub 7fffffff
#   CO | ???
#  Z O | ???
#
# JG/JNLE: ZF == 0 && SF == OF  - or - NOT(SF!=OF || ZF==1)
################################################################################

#		 DEC 	ADD-1	SUB 1
#		----- + ----- + -----
#  2 ->  1:	      |     C |  
#  1 ->  0:	  Z   |   Z C |   Z  
#  0 -> -1:	S     |	S     | S   C	LOCK_WRITE success
# -1 -> -2:	S     | S   C | S
#
# LOCK_WRITE: sub [sem], 1; jc success

.macro LOCK_WRITE sem
990:	lock sub dword ptr \sem, 1
	jc	999f
	lock inc dword ptr \sem
	YIELD#_SEM [\sem]
	jmp	990b
999:	
.endm

#		 INC    ADD 1
#		----- + ----- + -----
#  1 ->  2:	      |       |      	LOCK_READ success
#  0 ->  1:	      |       |      	LOCK_READ success
# -1 ->  0:	  Z   |   Z C |      
# -2 -> -1:	S     | S     |      
#
# LOCK_READ: inc [sem]; jg success

.macro LOCK_READ sem
990:	lock inc dword ptr \sem
	jg	999f
	lock dec dword ptr \sem
	YIELD
	jmp	990b
999:
.endm

.macro LOCK_READ_ sem
	pushf
	LOCK_READ \sem
	popf
.endm

.macro UNLOCK_READ sem
	lock dec dword ptr \sem
	# SF = 0: lock is >=0: jns success.
	# SF = 1: sem was <=0. Causes:
	# 1) too many read unlocks (bug), or:
	# 2) write lock attempted: interrupted at 2nd line (jc) in LOCK_WRITE.
	#    It will resolve on LOCK_WRITE's inc which will set sem to 0. 
	# x) LOCK_READ's DEC cannot be a cause due to it being preceeded by
	#    an INC resulting in a zero or positive contribution that cannot
	#    cannot make sem too negative.
.endm

.macro UNLOCK_READ_ sem
	pushf
	UNLOCK_READ \sem
	popf
.endm


.macro UNLOCK_WRITE sem
	lock inc dword ptr \sem
	# ZF = 1: success. Otherwise, ZF = 0, and:
	# SF = 0: sem was 0+. Causes:
	# 1) too many UNLOCK_WRITE (bug), or:
	# 2) read lock attempted (inc -1->0, released write lock, now 0->1).
	#    LOCK_READ will decrement (1->0) and try again.
	# x) LOCK_WRITE's INC cannot be a cause since it is preceeded by a SUB,
	#    which results in a zero or negative change that cannot contribute
	#    to sem being too positive.
	# SF = 1: sem was -2. Causes:
	# 1) too many UNLOCK_READ (bug), or:
	# 2) LOCK_WRITE attempted (dec -1->-2, now -2->-1).
	#    LOCK_WRITE will increment (-1->0) and try again.
	# x) LOCK_READ's DEC is not a cause as it is preceeded by INC, resulting
	#    in a change of 0 or +1 and thus cannot cause negativity.
.endm

.macro UNLOCK_WRITE_ sem
	pushf
	UNLOCK_WRITE \sem
	popf
.endm


# scheduler specific:

# timeout: -1 = infinity, other = ms
.macro YIELD_SEM sem, timeout=-1
	pushd	\timeout
	pushd	\sem
	KAPI_CALL task_wait_io
.endm

.endif
