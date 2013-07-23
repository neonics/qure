
.data
timing_foo: .space 1024
.text32
TIMING_NUM_MEASUREMENTS = 20

rdtsc_init:
	I "Measuring timer"
	call	newline

	call	more

	mov	ecx, cs
	mov	ebx, offset timer_calib_isr
	mov	ax, IRQ_TIMER + IRQ_BASE
	call	hook_isr
	PIC_GET_MASK
	push_	ebx ecx eax
	PIC_SET_MASK ~(1<<IRQ_TIMER)	# disable everything but the PIT

	mov	ecx, 20
	0: hlt; loop 0b


	pop_	eax ecx ebx
	PIC_SET_MASK
	mov	ax, IRQ_TIMER + IRQ_BASE
	call	hook_isr

	DEBUG_DWORD [timer_calib_count]
	call more
	ret


.data
timer_calib_count: .long 0
timer_tsc:	.long 0, 0
.text32
timer_calib_isr:
	inc	dword ptr [timer_calib_count]
#	test	byte ptr [timer_calib_count], 7
#	jnz	1f
	push_	eax edx
#	pushad; cpuid; popad
	rdtsc
	xchg	[timer_tsc + 0], eax
	xchg	[timer_tsc + 4], edx
	sub	eax, [timer_tsc + 0]
	sbb	edx, [timer_tsc + 4]
	not	eax
	not	edx
	DEBUG_DWORD edx
	DEBUG_DWORD eax
	call	newline

	pop_	edx eax
1:	PIC_SEND_EOI IRQ_TIMER
	iret


timer_calib_0:
	xor	ecx, ecx
0:	call	get_time_ms_40_24
	push_	edx eax

	shld	edx, eax, 8
	lea	ebx, [edx + 30]	# 100 ms

	rdtsc
	mov	edi, edx
	mov	esi, eax

1:	hlt
	call	get_time_ms
	cmp	eax, ebx
	jb	1b

	call	get_time_ms_40_24
	sub	eax, [esp]
	sbb	edx, [esp+4]
	mov	[esp], eax
	mov	[esp+4], edx
	rdtsc
	sub	eax, esi
	sbb	edx, edi

	#DEBUG "TSC: "
	#DEBUG_DWORD edx
	#DEBUG_DWORD eax
	#DEBUG "PIT: "
	pop	esi
	pop	edi
	#DEBUG_DWORD edi
	#DEBUG_DWORD esi
	# edx:eax = 0:15......
	# edi:esi = 0:66......
	# calc ticks per ms
	mov	edx, eax
	xor	eax, eax
	div	esi

	mov	[timing_foo+ecx+0], edx
	mov	[timing_foo+ecx+4], eax

	#call	newline
	add	ecx, 8
	cmp	ecx, 8*TIMING_NUM_MEASUREMENTS
	jb	0b

	xor	esi, esi
	xor	ebx, ebx
	xor	ecx, ecx
	xor	edx, edx
	xor	eax, eax
0:	add	eax, [timing_foo+esi+4]
	adc	edx, 0
	inc	ecx
	add	esi, 8
	cmp	esi, 8*TIMING_NUM_MEASUREMENTS
	jb	0b

	div	ecx
	# eax = average
	DEBUG_DWORD eax,"avg"

	# calc difference
	xor	ebx, ebx	# avg diff
	xor	ecx, ecx
	xor	edi, edi
	xor	esi, esi
0:	mov	edx, [timing_foo+esi+4-8]
	sub	edx, [timing_foo+esi+4]
	jns	1f	# abs diff
	neg	edx
1:	mov	[timing_foo+esi], edx	# diff
	inc	ecx
	add	ebx, edx
	adc	edi, 0
	add	esi, 8
	cmp	esi, 8*TIMING_NUM_MEASUREMENTS
	jb	0b

	mov	eax, ebx
	mov	edx, edi
	div	ecx

	DEBUG_DWORD eax, "avg diff"
	call	newline
	lea	ebx, [eax * 2]

	xor	esi, esi
0:	DEBUG_DWORD [timing_foo+esi+0],"diff"
	DEBUG_DWORD [timing_foo+esi+4],"eax"
	mov	edx, ebx
	sub	edx, [timing_foo+esi]
	DEBUG_DWORD edx,"diffdiff"
	call	newline
	add	esi, 8
	cmp	esi, 8*TIMING_NUM_MEASUREMENTS
	jb	0b




	

call more
	ret


get_time_test$:
	call	get_time_ms
	mov	edx, eax
		xor	ecx, ecx
0:	call	get_time_ms
		inc	ecx
	cmp	edx, eax
	jz	0b
	mov	edx, eax
	PUSH_SCREENPOS
	call	printdec32
		call	printspace
		push edx
		mov	edx, ecx
		call	printdec32
		pop edx
		xor	ecx, ecx
	POP_SCREENPOS
	jmp	0b

	mov	ecx, 10
0:	push	ecx
	call	rdtsch_measure$
	pop	ecx
	loop	0b
	ret

rdtsch_measure$:
	rdtsc
	mov	esi, eax
	mov	edi, edx
	call	get_time_ms
	mov	edx, eax

		mov	eax, [clock_ms]
		mov	edx, eax
	add	eax, 1000
0:	cmp	eax, [clock_ms]
	jb	1f
	hlt
	jmp	0b
1:	
	mov	eax, [clock_ms]
	sub	eax, edx
	mov	ecx, eax

call	get_time_ms
mov	ebx, eax
DEBUG_DWORD ebx
	rdtsc
	sub	eax, esi
	sbb	edx, edi
	mov	esi, eax
	mov	edi, edx

	print " Time: "
	mov	edx, ecx
	call	printdec32
	print "ms RDTSC: "

	mov	edx, edi
	call	printhex8
	mov	edx, esi
	call	printhex8

.if 1
	call	get_time_ms
DEBUG_DWORD eax
	sub	eax, ebx
	mov	ebx, eax

	print " time: "
	mov edx, ebx
	call	printdec32

	mov	edx, edi
	mov	eax, esi
	div	ebx

	print " TSC/ms: "
	mov	bl, 7
	call	print_fixedpoint_32_32$

.else
	mov	edx, edi
	mov	eax, esi
	div	ecx

	print " TSC/ms: "
	mov	bl, 7
	call	print_fixedpoint_32_32$

	call get_time_ms
	sub eax, ebx
	mov edx, eax
	print " time: "
	call printdec32
.endif
	call	newline
	ret

