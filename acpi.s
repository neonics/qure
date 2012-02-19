# http:#forum.osdev.org/viewtopic.php?t=16990

.intel_syntax noprefix
.text

	.macro FLAT2SO seg, offs
		push	eax
		mov	\offs, eax
		shr	eax, 4
		mov	\seg, ax
		and	\offs, 0x0f
		pop	eax
	.endm


.data
SMI_CMD:	.word 0 # dword ptr
ACPI_ENABLE:	.byte 0;
ACPI_DISABLE:	.byte 0;
PM1a_CNT:	.word 0 # dword ptr
PM1b_CNT:	.word 0 # dword ptr
SLP_TYPa:	.word 0
SLP_TYPb:	.word 0
SLP_EN:		.word 0
SCI_EN:		.word 0
PM1_CNT_LEN:	.byte 0

#.struct RSDP
#{
#				;[L/O] length / offset
#  signature	db 'RSD PTR '	;[8/0]
#  checksum	db ?		;[1/8] first 20 bytes, starting at signature
#  oemid	db 6 dup(?)	;[6/9]
#  revision	db ?		;[1/15] 1.0=0, cur spec (5.0?) = 2
#  rsdt_addr	dd ?		;[4/16] 32 bit address of RSDT
#  len		dd ?		;[4/20] length of entire table incl header
#  xsdt_addr	dq ?		;[8/24] 8bytes, 64 bit address of XSFT
#  ext_checksum	db ?		;[1/32] checksum of entire table
#  reserved	db 3 dup(?)	;[3/33]
#};


.struct 0
RSDP_signature:
.struct 8
RSDP_checksum:
.struct 9
RSDP_oemid:
.struct 15
RSDP_revision:
.struct 16
RSDP_rsdt_addr:
.struct 20
RSDP_len:
.struct 24
RSDP_xsdt_addr:
.struct 32
RSDP_ext_checksum:
.text

.macro ACPI_MAKE_SIG a, b, c, d
	mov	ebx, (\d << 24) + (\c <<16) + (\b <<8) + (\a)
.endm

.macro PRINTSIG
	push	ebx
	push	ax
	mov	ah, 0x1f
	.rept 4
	mov	al, bl
	stosw
	shr	ebx, 8
	.endr
	pop	ax
	pop	ebx
.endm

# return cf 1 = not found, eax 0
# return cf 0 = found, eax = flat address
# Root System Description Pointer
acpi_get_rsdp$:
	push	esi
	push	ecx


	# first 1kb of ebda
	push	ds
	xor	esi, esi
	mov	ds, si
	mov	si, [0x40e] # EBDA segment
	pop	ds
	shl	esi, 4

	mov	ecx, 1024 >> 2
0:	call	acpi_check_rsdp$
	mov	eax, esi
	jz	1f
	add	esi, 16
	loop	0b

	# not found in ebda, try 0xe0000-0x0fffff
	# just before 1MB
	mov	esi, 0xe0000

0:	call	acpi_check_rsdp$
	mov	eax, esi
	jz	1f
	add	esi, 16
	cmp	esi, 0x10 << 4
	jl	0b


2:	PRINTLNc 0xf4 "RSDP not found"
	xor	eax, eax
	stc
0:	pop	ecx
	pop	esi
	ret

1:	mov	ah, 0xf2
	PRINT	"RSDP found @ "
	push	edx
	mov	edx, esi
	ror	edx, 16
	call	printhex
	sub	di, 2
	ror	edx, 16
	call	printhex


	mov	eax, esi
	push	fs
	push	ebx
	FLAT2SO fs, ebx

	mov	ah, 0xf0
	PRINT	"OEMID: "
	mov	al, fs:[ebx + RSDP_oemid + 0]
	stosw
	mov	al, fs:[ebx + RSDP_oemid + 1]
	stosw
	mov	al, fs:[ebx + RSDP_oemid + 2]
	stosw
	mov	al, fs:[ebx + RSDP_oemid + 3]
	stosw
	mov	al, fs:[ebx + RSDP_oemid + 4]
	stosw
	mov	al, fs:[ebx + RSDP_oemid + 5]
	stosw

	push	edx
	PRINT	"Rev "
	mov	dl, fs:[ebx + RSDP_revision]
	call	printhex2

	PRINT	"RSDT: 0x"
	mov	edx, fs:[ebx + RSDP_rsdt_addr]
	ror	edx, 16
	call	printhex
	sub	di, 2
	ror	edx, 16
	call	printhex
	pop	edx

	pop	ebx
	pop	fs

	call	newline
	pop	edx

	mov	eax, esi
	clc
	jmp	0b

#########

# char * ax, char * bx, int cx
# ret: flags
_memcmp$:
	push	ax
	push	dx
	push	si
	push	di
	push	es
	mov	si, ds
	mov	es, si
	mov	di, bx
	mov	si, ax
	rep	cmpsb
	pop	es
	pop	di
	pop	si
	pop	dx
	pop	ax
	ret


# in: esi flat ptr
# out: zf
acpi_check_rsdp$:
	push	eax
	push	cx
	push	si
	push	di
	push	es

	# make es:di point to mem to examine
	mov	eax, esi
	shr	eax, 4
	mov	es, ax
	and	eax, 0xf
	mov	di, ax

	.data
	acpi_rsdp_sig$: .ascii "RSD PTR "
	.text

	push	di
	mov	si, offset acpi_rsdp_sig$
	mov	cx, 8
	rep	cmpsb
	pop	di
	jnz	0f


0:	pop	es
	pop	di
	pop	si
	pop	cx
	pop	eax
	ret




# checks for a given header and validates checksum
# in: eax = ptr to ACPI object, ebx = "ABCD" sig
# out: zf == cf : 1 = no match
acpi_check_header$:
	push	eax
	push	esi
	push	dx
	push	ds

PRINTc	0xf1 "Checking signature: "
PRINTSIG
#jmp	2f

	mov	esi, eax
	shr	eax, 4
	mov	ds, ax
	and	esi, 0x0f

	cmp	ebx, [si]
	jnz	2f
	mov	dx, 0x0447
	call	printhex
0:	
	add	si, 4
	mov	cx, [si] #assume size is 2 

	mov	dx, cx
	call	printhex

	.if 0
	#xor	ax, ax
	#rep	addsw
	.else
	xor	dx, dx
0:	lodsw
	add	dx, ax
	loop	0b
	.endif
	or	dx, dx
	jnz	2f	# maybe with a cmc here somewhere...
	clc
	jmp	1f

2:	mov	dx, 0xfa11
	call	printhex
	push	ebx
	mov	ebx, [si]
	PRINTSIG
	call	newline
	pop	ebx
	stc
1:	pop	ds
	pop	dx
	pop	esi
	pop	eax
	ret



acpi_enable:
	call	acpi_init
	jc	no_acpi$

	mov	dx, [PM1a_CNT]
	in	ax, dx
	or	ax, ax
	jz	0f

	PRINTLNc 4 "ACPI already enabled"

	clc
	ret
0:
	mov	dx, [SMI_CMD]
	mov	al, [ACPI_ENABLE]
	or	dx, dx
	jz	0f
	or	al, al
	jz	0f
	PRINTLNc 3 "Enabling ACPI"
	out	dx, al

# need timer
	mov	dx, [PM1a_CNT]
	in	ax, dx
	test	ax, [SCI_EN]
	jnz	1f

	mov	dx, [PM1b_CNT]
	or	dx, dx
	jz	0f
	in	ax, dx
	test	ax, [SCI_EN]
	jnz	1f
	PRINTLNc 4 "Failed to initialize ACPI"
	stc
	ret
1: 	clc
	ret

0:	PRINTLNc 4 "not enough ACPI information to enable"
	stc
	ret



#
# bytecode of the \_S5 object
# -----------------------------------------
#        | (optional) |    |    |    |   
# NameOP | \          | _  | S  | 5  | _
# 08     | 5A         | 5F | 53 | 35 | 5F
#
# -----------------------------------------------------------------------------------------------------------
#           |           |              | ( SLP_TYPa   ) | ( SLP_TYPb   ) | ( Reserved   ) | (Reserved    )
# PackageOP | PkgLength | NumElements  | byteprefix Num | byteprefix Num | byteprefix Num | byteprefix Num
# 12        | 0A        | 04           | 0A         05  | 0A          05 | 0A         05  | 0A         05
#
#----this-structure-was-also-seen----------------------
# PackageOP | PkgLength | NumElements |
# 12        | 06        | 04          | 00 00 00 00
#
# (Pkglength bit 6-7 encode additional PkgLength bytes [shouldn't be the case here])
#

#
#struct FACP
#{
#   byte Signature[4];
#   dword Length;
#   byte unneded1[40 - 8];
.equ FACP_DSDT, 1 + 4 + 32 
#   dword *DSDT;
#   byte unneded2[48 - 44];
.equ FACP_SMI_CMD, FACP_DSDT + 4  + 4
#   dword *SMI_CMD;
.equ FACP_ACPI_ENABLE, FACP_SMI_CMD + 4
.equ FACP_ACPI_DISABLE, FACP_ACPI_ENABLE + 1
#   byte ACPI_ENABLE;
#   byte ACPI_DISABLE;
#   byte unneded3[64 - 54];
.equ FACP_PM1a_CNT_BLK, FACP_ACPI_DISABLE + 12
#   dword *PM1a_CNT_BLK;
.equ FACP_PM1a_CNT_BLK, FACP_ACPI_DISABLE + 12 + 4
#   dword *PM1b_CNT_BLK;
#   byte unneded4[89 - 72];
.equ FACP_PM_CNT_LEN, FACP_ACPI_DISABLE + 12 + 4 + 4 + 89-72
#   byte PM1_CNT_LEN;
#};
#


############# acpi_init local utility functions ##############
#{
#   unsigned int *ptr = acpiGetRSDPtr();
#
#   # check if address is correct  ( if acpi is available on this pc )
#   if (ptr != NULL && acpiCheckHeader(ptr, "RSDT") == 0)
#   {
#
.data
msg_no_acpi$: .asciz "No ACPI available"
.text
no_acpi$:	PRINTLNc 0xf2 "No ACPI available"
		stc
		ret
######

acpi_init:	
	.data
		acpi_initialized$: .byte 0
	.text

	cmp	byte ptr [acpi_initialized$], 0
	jz	0f
	clc
	ret

0:	PRINTLNc 0xf1 "Checking ACPI availability"
	call	acpi_get_rsdp$	# result: eax flat ptr
	jc	no_acpi$

	PRINTLNc 0xf0 "Checking RSDT"

	FLAT2SO fs, esi
	mov	eax, fs:[esi + RSDP_rsdt_addr]
	push	ax
	mov	edx, eax
	mov	ah, 0xf2
	call	printhex8
	pop	ax

	ACPI_MAKE_SIG 'R','S','D','T'
	call	acpi_check_header$
	jc	no_acpi$

	PRINTLNc 0xf0 "Analyzing data structure"

	# General format: 36 bytes header
	# 4 byte pointers

	.macro ERR a
		.data
		9: .asciz "\a"
		.text
		mov	si, offset 9b
		jmp	err$
	.endm


	FLAT2SO	fs, esi
      	mov	ecx, fs:[esi+4]
	sub	ecx, 36
	shr	ecx, 2
	add	si, 36		# skip header
	add	eax, 36

loop$:
         # check if the desired table is reached
#         if (acpiCheckHeader((unsigned int *) *ptr, "FACP") == 0)
	ACPI_MAKE_SIG 'F','A','C','P'
	call	acpi_check_header$
	jc	0f

	PRINTLNc 0xf2 "Found FACP signature"

	sub	cx, 2 # ?

	# reference facp->dsdt (pointer to dsdt)
 	push	eax
	FLAT2SO	fs, esi
	mov	eax, fs:[si + FACP_DSDT]
	ACPI_MAKE_SIG 'D','S','D','T'
	call	acpi_check_header$
	pop	eax

	jnc	1f
	ERR "FACP->DSDT checksum error"

1:
	mov	edx, fs:[si + 1] # len
	sub	dx, 36

	# here fs:si deviates from eax (nested pointer)

	add	si, 36 # skip header
	ACPI_MAKE_SIG '_', 'S', '5', '_'
2:	cmp	fs:[si], ebx
	jz	2f
	add	si, 1	# or 4?
	dec	dx
	jge	2b

	#ERR "_S5_ not present"
	jmp	0f
2:	


# if ( ( *(S5Addr-1) == 0x08 || ( *(S5Addr-2) == 0x08 && *(S5Addr-1) == '\\') ) && *(S5Addr+4) == 0x12 )
# check for valid AML structure
#{
	mov	dl, fs:[si - 1]
	cmp	dl, 8
	jz	1f
	cmp	dl, '\'
	jnz	0f
	mov	al, fs:[si - 2]
	cmp	al, 8
	jnz	0f
	mov	al, fs:[si + 4]
	cmp	al, 0x12
	jnz	0f
1:
	PRINTLNc 0xf0 "Found valid AML structure"
#S5Addr += 5;
#S5Addr += ((*S5Addr &0xC0)>>6) +2;   # calculate PkgLength size
	add	si, 5
	mov	dx, si
	and	dx, 0xc0
	sar	dx, 6
	add	dx, 2
	add	si, dx

	cmp	fs:[si], byte ptr 0xa0 # skip byte pfx
	jnz	1f
	inc	si
1:	mov	dx, fs:[si]
	shl	dx, 10
	mov	[SLP_TYPa], dx
	inc	si

	cmp	fs:[si], byte ptr 0xa0
	jnz	1f
	inc	si
1:	mov	dx, fs:[si]
	shl	dx, 10
	mov	[SLP_TYPb], dx

	FLAT2SO	fs, esi
	mov	dx, fs:[si + FACP_SMI_CMD]
	mov	[SMI_CMD], dx

	mov	dx, fs:[si + FACP_ACPI_ENABLE]
	mov	[API_ENABLE], dx

	mov	dx, fs:[si + FACP_ACPI_DISABLE]
	mov	[API_DISABLE], dx

	mov	dx, fs:[si + FACP_PM1a_CNT_BLK]
	mov	[PM1a_CNT], dx

	mov	dx, fs:[si + FACP_PM1b_CNT_BLK]
	mov	[PM1b_CNT], dx

	mov	dx, fs:[si + FACP_PM1_CNT_LEN]
	mov	[PM1_CNT_LEN], dx
                     
	mov	word ptr [SLP_EN], 1 << 13
	mov	word ptr [SCI_EN], 1

	clc
	PRINTLNc 3 "ACPI found"
	ret


0: 	add	si, 4
	
	dec	cx
	jge	loop$

	ERR	"No ACPI"

err$:	
	PRINTc 0x2f "Error: "
	mov	ah, 2
	call	println
	stc
	ret



acpi_poweroff:	
	PRINTLNc 0xf2 "ACPI poweroff called"

	push	ax
	call	acpi_init
	pop	ax
	jc	no_acpi$
	
	cmp	word ptr [SCI_EN], 0	# shutdown possibility
	jz	no_acpi$

	call	acpi_enable

	mov	dx, [PM1a_CNT]
	mov	ax, [SLP_TYPa]
	or	ax, [SLP_EN]
	out	dx, ax
# possible shutdown may have occurred

	mov	dx, [PM1b_CNT]
	or	dx, dx
	jz	0f
	mov	ax, [SLP_TYPb]
	or	ax, [SLP_EN]
	out	dx, ax
0:	
	mov	ah, 0xf4
	PRINT	"ACPI Shutdown failure"
	ret

#void acpiPowerOff(void)
#{
#   # SCI_EN is set to 1 if acpi shutdown is possible
#   if (SCI_EN == 0)
#      return;
#
#   acpiEnable();
#
#   # send the shutdown command
#   outw((unsigned int) PM1a_CNT, SLP_TYPa | SLP_EN );
#   if ( PM1b_CNT != 0 )
#      outw((unsigned int) PM1b_CNT, SLP_TYPb | SLP_EN );
#
#   wrstr("acpi poweroff failed.\n");
#}
#

