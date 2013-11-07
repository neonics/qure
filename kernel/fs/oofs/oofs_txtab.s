#############################################################################
.intel_syntax noprefix

.struct 0
txtab_sha1: .space 20
txtab_size: .long 0
txtab_lba:  .long 0
.long 0

DECLARE_CLASS_BEGIN oofs_txtab, oofs_array

oofs_txtab_array:	# passed to super

DECLARE_CLASS_METHOD oofs_api_init, oofs_txtab_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_array_api_print_el, oofs_txtab_print_el, OVERRIDE

DECLARE_CLASS_METHOD oofs_txtab_api_lookup, oofs_txtab_lookup

DECLARE_CLASS_END oofs_txtab
#################################################
.text32
# in: eax = instance
# in: edx = parent (instace of class_oofs_vol)
# in: ebx = LBA
# in: ecx = reserved size
oofs_txtab_init:
	movb	[eax + oofs_array_shift], 5
	mov	[eax + oofs_array_start], dword ptr offset oofs_txtab_array
	mov	[eax + oofs_array_persistent_start], dword ptr offset oofs_txtab_array
	call	oofs_array_init	# super.init()

	.if 1#OOFS_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_txtab_init"
		printc 9, " LBA=";  push ebx; call _s_printhex8
		printc 9, " size="; push ecx; call _s_printhex8
		printc 9, " parent="; PRINT_CLASS edx
		call	newline
	.endif
	clc
	ret


# in: eax = this
# in: edx = txtab
# out: CF = 0: edx valid; 1: ebx = -1, edx unmodified
# out: ecx = index in parent table (ecx since oofs_load_entry expects it)
oofs_txtab_lookup:
	STACKTRACE 0
	ret

oofs_txtab_print_el:
	ret

