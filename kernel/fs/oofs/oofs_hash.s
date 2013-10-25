#############################################################################
.intel_syntax noprefix

OOFS_HASH_DEBUG = 1

.struct 0
hash_sha1: .space 20
hash_size: .long 0
hash_lba:  .long 0
.long 0

DECLARE_CLASS_BEGIN oofs_hash, oofs_array

oofs_hash_array:	# passed to super

DECLARE_CLASS_METHOD oofs_api_init, oofs_hash_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_array_api_print_el, oofs_hash_print_el, OVERRIDE

DECLARE_CLASS_METHOD oofs_hash_api_lookup, oofs_hash_lookup

DECLARE_CLASS_END oofs_hash
#################################################
.text32
# in: eax = instance
# in: edx = parent (instace of class_oofs_vol)
# in: ebx = LBA
# in: ecx = reserved size
oofs_hash_init:
	movb	[eax + oofs_array_shift], 5
	mov	[eax + oofs_array_start], dword ptr offset oofs_hash_array
	mov	[eax + oofs_array_persistent_start], dword ptr offset oofs_hash_array
	call	oofs_persistent_init	# super.init()

	.if OOFS_DEBUG
		PRINT_CLASS
		printc 14, ".oofs_hash_init"
		printc 9, " LBA=";  push ebx; call _s_printhex8
		printc 9, " size="; push ecx; call _s_printhex8
		printc 9, " parent="; PRINT_CLASS edx
		call	newline
	.endif
	ret


# in: eax = this
# in: edx = hash
# out: CF = 0: edx valid; 1: ebx = -1, edx unmodified
# out: ecx = index in parent table (ecx since oofs_load_entry expects it)
oofs_hash_lookup:
	STACKTRACE 0
	ret

oofs_hash_print_el:
	ret

