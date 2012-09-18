.intel_syntax noprefix
.text
.code32

.macro BREAKPOINT label
	pushf
	push 	eax
	PRINTC 0xf0, "\label"
	xor	eax, eax
	call	keyboard
	pop	eax
	popf
.endm

BREAKPOINT "foo"

.data SECTION_DATA_BSS
debug_registers$: .space 4 * 32
.text

debug_regstore$:
	mov	[debug_registers$ + 4 * 0], eax
	mov	[debug_registers$ + 4 * 1], ebx
	mov	[debug_registers$ + 4 * 2], ecx
	mov	[debug_registers$ + 4 * 3], edx
	mov	[debug_registers$ + 4 * 4], esi
	mov	[debug_registers$ + 4 * 5], edi
	mov	[debug_registers$ + 4 * 6], ebp
	mov	[debug_registers$ + 4 * 7], esp
	sub	[debug_registers$ + 4 * 7], dword ptr 6	# pushf/pushcolor adjust
	mov	[debug_registers$ + 4 * 8], cs
	mov	[debug_registers$ + 4 * 9], ds
	mov	[debug_registers$ + 4 * 10], es
	mov	[debug_registers$ + 4 * 11], ss
	ret


.macro DEBUG_REGDIFF0 nr, reg
	cmp	[debug_registers$ + 4 * \nr], \reg
	jz	88f
	print	"\reg: "
	push	edx
	mov	edx, [debug_registers$ + 4 * \nr]
	call	printhex8
	print	" -> "
	pop	edx
	push	edx
	mov	edx, \reg
	.if \reg == esp
	add	edx, 6
	.endif
	call	printhex8
	pop	edx
	call	newline
88:
.endm

.macro DEBUG_REGDIFF1 nr, reg
	push	eax
	mov	eax, \reg
	DEBUG_REGDIFF0 \nr, eax
	pop	eax
.endm


debug_regdiff$:
	pushf
	pushcolor 0xf4
	DEBUG_REGDIFF0 0, eax
	DEBUG_REGDIFF0 1, ebx
	DEBUG_REGDIFF0 2, ecx
	DEBUG_REGDIFF0 3, edx
	DEBUG_REGDIFF0 4, esi
	DEBUG_REGDIFF0 5, edi
	DEBUG_REGDIFF0 6, ebp
	DEBUG_REGDIFF0 7, esp
	DEBUG_REGDIFF1 8, cs
	DEBUG_REGDIFF1 9, ds
	DEBUG_REGDIFF1 10, es
	DEBUG_REGDIFF1 11, ss
	popcolor
	popf
	ret


.macro DEBUG_REGSTORE name=""
	DEBUG "\name"
	call	debug_regstore$
.endm
.macro DEBUG_REGDIFF
	call	debug_regdiff$
.endm


