.intel_syntax noprefix

.text
.code32

# in: eax = base, ecx = number of entries
ll_alloc:
	mov	ecx, eax
	imul	eax, 3
	call	kalloc
	ret



