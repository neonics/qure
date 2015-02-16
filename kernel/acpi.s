# http:#forum.osdev.org/viewtopic.php?t=16990
.intel_syntax noprefix

ACPI_DEBUG = 0

.data SECTION_DATA_BSS
acpi_rsdp:	.long 0	# ds relative ptr
acpi_fadt:	.long 0	# ds relative ptr
acpi_addr_reloc$: .long 0 # add this to PTRs in ACPI structures for ds rel
.text32

acpi_init:
	I "Detecting ACPI "
	call	acpi_get_rsdp$
	jc	9f
	print " Found RSDP at "
	mov	edx, [acpi_rsdp]
	call	printhex8
	call	newline
	call	acpi_enable
#call more
	ret
9:	printlnc 12, "No ACPI"
	ret


.macro ACPI_MAKE_SIG reg, a, b, c, d
	mov	\reg, (\d << 24) + (\c <<16) + (\b <<8) + (\a)
.endm

.macro PRINTSIG
	push	ebx
	push	ax
	mov	ah, 0x1f
	.rept 4
	mov	al, bl
	call	printcharc
	shr	ebx, 8
	.endr
	pop	ax
	pop	ebx
.endm

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
RSDP_signature:	.long 0,0	# 8
RSDP_checksum:	.byte 0		# 9
RSDP_oemid:	.space 6	# 15
RSDP_revision:	.byte 0		# 16
RSDP_rsdt_addr:	.long 0		# 20
RSDP_len:	.long 0
RSDP_xsdt_addr:	.long 0,0
RSDP_ext_checksum:.byte 0
		.space 3
.text32
# return cf 1 = not found, eax 0
# return cf 0 = found, eax = flat address
# Root System Description Pointer
# 000f 6b80: "RSD PTR "
acpi_get_rsdp$:
	push	fs
	mov	di, SEL_flatDS
	mov	fs, di

	# EBDA is located in highest memory just under 640K on PS/2
	# word at BIOS Data Area 40:0E is segment address of EBDA
	# first 1kb of ebda
	movzx	edi, word ptr [0x40e] # EBDA segment
	shl	edi, 4
	mov	ecx, 1024*1024 / 16
	call	acpi_scan$
	jnc	1f

	# not found in ebda, try 0xe0000-0x0fffff
	# just before 1MB
	mov	edi, 0x000e0000
	mov	ecx, 0x0001ffff/16
	call	acpi_scan$
	jnc	1f

0:	pop	fs
	ret

1:	GDT_GET_BASE eax, ds
	neg	eax
	mov	[acpi_addr_reloc$], eax
	add	eax, edi
	mov	[acpi_rsdp], eax
	mov	ebx, eax

	.if ACPI_DEBUG
		DEBUG_DWORD eax, "ACPI RSDP"
	.endif


	PRINT	"OEMID: "
	mov	ecx, 6
	lea	esi, [ebx + RSDP_oemid]
	call	nprint

	PRINT	" Rev "
	mov	dl, [ebx + RSDP_revision]
	call	printhex2

	mov	edx, [ebx + RSDP_rsdt_addr]
	.if ACPI_DEBUG
		PRINT	" RSDT: "
		call	printhex8
		call	newline
	.endif

	call	acpi_check_rsdt	# out: CF
	jmp	0b


# in: fs = flatseg
# in: edi = start
# in: ecx = len
acpi_scan$:
0:	cmpd	fs:[edi+0], 'R'|('S'<<8)|('D'<<16)|(' '<<24)
	jnz	3f
	cmpd	fs:[edi+4], 'P'|('T'<<8)|('R'<<16)|(' '<<24)
	jz	1f
3:	add	edi, 16
	loop	0b
	stc
	ret

1:	# verify checksum
	xor	dl, dl
	push_	edi ecx
	mov	ecx, 20
2:	add	dl, fs:[edi]
	inc	edi
	loop	2b
	pop_	ecx edi
	or	dl, dl
	jnz	0b	# wrong checksum

	clc
	ret

SHELL_COMMAND "acpi", cmd_acpi
cmd_acpi:
#	call	acpi_init
#	call	acpi_enable
	call	acpi_reboot
#	call	acpi_shutdown
	ret

##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
	.macro FLAT2SO seg, offs
		push	eax
		mov	\offs, eax
		shr	eax, 4
		mov	\seg, ax
		and	\offs, 0x0f
		pop	eax
	.endm


.data
SLP_TYPa:	.word 0	# 3bit value
SLP_TYPb:	.word 0	# 3bit value

#########


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

.struct 0	# all tables, except RSDP/FACS
acpi_tbl_sig:		.long 0
acpi_tbl_size:		.long 0
acpi_tbl_rev:		.byte 0
acpi_tbl_cksum:		.byte 0
acpi_tbl_oemid:		.space 6
acpi_tbl_oem_tbl_id:	.space 8
acpi_tbl_oem_rev:	.long 0
acpi_tbl_cmplr_id:	.long 0	# ascii ASL compiler vendor id
acpi_tbl_cmplr_rev:	.long 0	# ascii ASL compiler vendor id
ACPI_TBL_HDR_SIZE = . # 36


.struct 0 # acpi_generic_address structure (GAS)
acpi_addr_space:	.byte 0
	# 0=system mem
	# 1=system IO
	# 2=pci config space
	# 3=embedded controller
	# 4=SMBus
	# 5-0x7e reserved
	# 0x7f=functional fixed hardware
	# 0x80-0xbf reserved
	# 0xc0-0xff OEM defined
acpi_addr_bitwidth:	.byte 0
acpi_addr_bitoffs:	.byte 0
acpi_addr_xs_size:	.byte 0	# 0=undef; 1=byte,2=word;3=long;4=qword
acpi_addr_addr:		.long 0, 0
ACPI_GAS_SIZE = .


.struct ACPI_TBL_HDR_SIZE	# FACP; (FADT: sig "FACP" fixed acpi desc tab)
FADT_FACS_ptr:		.long 0
FADT_DSDT_ptr:		.long 0
FADT_model:		.byte 0
FADT_preferred_profile:	.byte 0
FADT_SCI_interrupt:	.word 0

FADT_SMI_CMD_PORT:	.long 0	# SMI command port
FADT_ACPI_ENABLE:	.byte 0
FADT_ACPI_DISABLE:	.byte 0
FADT_S4_BIOS_REQUEST:	.byte 0

FADT_pstate_control:	.byte 0

FADT_PM1a_EVT_BLK_PORT:	.long 0	# event
FADT_PM1b_EVT_BLK_PORT:	.long 0	# event
FADT_PM1a_CNT_BLK_PORT:	.long 0 # control
FADT_PM1b_CNT_BLK_PORT:	.long 0 # control
	# pm1 control reg fixed hardware feat ctrl
	PM1_SCI_EN	= 1<<0#1=sci, 0=smi
	PM1_BM_RLD	= 1<<1	# busmaster req c3->c0
	PM1_GBL_RLS	= 1<<2	# w/o: gen SMI->BIOS
	PM1_SLP_TYP	= 0b111<<10 # sleep state for SLP_EN (\_Sx)
	PM1_SLP_EN	= 1<<13


FADT_PM2_CNT_BLK_PORT:	.long 0 # control
FADT_PM_TIMER_BLK_PORT:	.long 0 # control
FADT_GP_EVT0_BLK_PORT:	.long 0 # general purpose event 0 reg blk
FADT_GP_EVT1_BLK_PORT:	.long 0 # general purpose event 1 reg blk
FADT_PM1_EVT_LEN:	.byte 0
FADT_PM1_CNT_LEN:	.byte 0
FADT_PM2_CNT_LEN:	.byte 0
FADT_PM_TIMER_LEN:	.byte 0
FADT_GP_EVT0_BLK_LEN:	.byte 0
FADT_GP_EVT1_BLK_LEN:	.byte 0
FADT_GP_EVT1_BASE:	.byte 0	# offset in gpe nrs
FADT_CST_CNT:		.byte 0 # C-State control
FADT_C2_LATENCY:	.word 0
FADT_C3_LATENCY:	.word 0
.word 0,0 # word flush_size,flush_stride
.byte 0,0,0,0,0 # byte duty_offs,duty_width,day_alarm,month_alarm,century (RTC CMOS RAM)
.word 0 # word boot_flags
.byte 0 # byte reserved
.long 0 # long flags
FADT_reset_reg: .space ACPI_GAS_SIZE # struct generic_address reset_register
FADT_reset_val: .byte 0 # byte reset_value
.space 3	# reserved
# long reserved
### The rest below 64 bit stuff:
# 64bit xfacs, xdsdt
# struct_generic_address xpm1a_evt_blk,xpm1b_evt_blk,xpm1a_ctrl_blk,xpm1b_ctrl_blk,
#    xpm2_ctrl_blk, xpm_timer_blk, xgpe0_blk,xgpe1_blk,sleep_ctrl,sleep_status

.text32


############# acpi_init local utility functions ##############
.text32
no_acpi$: printlnc 12, "no ACPI"
	ret

acpi_check_rsdt:
	.if ACPI_DEBUG
		DEBUG "Checking RSDT"
	.endif

	mov	eax, [acpi_rsdp]
	mov	eax, [eax + RSDP_rsdt_addr]
	add	eax, [acpi_addr_reloc$]
	.if ACPI_DEBUG
		DEBUG_DWORD eax,"addr"
	.endif


	ACPI_MAKE_SIG ebx, 'R','S','D','T'
	call	acpi_check_header$
	jc	no_acpi$

	.if ACPI_DEBUG
		DEBUG "RSDT subtables:"
	.endif
	pushad
	mov	ecx, [eax + 4]
	sub	ecx, 36
	shr	ecx, 2
	jz	1f
	mov	esi, eax
	add	esi, 36
0:	mov	ebx, [esi]
	add	esi, 4
	mov	ebx, [ebx]
	.if ACPI_DEBUG
		PRINTSIG		# FACP BOOT APIC MCFG SRAT HPET WAET
		call	printspace
	.endif
	loop	0b
1:	popad

	.if ACPI_DEBUG
		call	newline
		PRINTLNc 0xf0 "Analyzing data structure"
	.endif

	mov	ecx, [eax + 4]	# len
	add	eax, 36		# skip header
	sub	ecx, 36
	.if ACPI_DEBUG
		DEBUG_DWORD ecx
	.endif
	# lets shr because we add 4:
	shr	ecx, 2
	jecxz	3f

0:	push_	eax ecx
	mov	eax, [eax]
	add	eax, [acpi_addr_reloc$]
	ACPI_MAKE_SIG ebx, 'F','A','C','P'
	call	acpi_check_header$
	jc	1f

	call	acpi_check_facp$
	jnc	2f

1: 	pop_	ecx eax
	add	eax, 4
	loop	0b
3:	printlnc 4, "FACP not found"
	stc
0:	ret

2:
	.if ACPI_DEBUG
		DEBUG_DWORD eax, "Found FACP"
	.endif
	pop_	ecx eax
	ret


acpi_check_facp$:
	pushad

	mov	[acpi_fadt], eax

	.if ACPI_DEBUG
		print "FADT ('FACP') found: "

		DEBUG_DWORD [eax + acpi_tbl_size]
		DEBUG_DWORD [eax + FADT_DSDT_ptr]
		DEBUG_DWORD [eax + FADT_SMI_CMD_PORT]
		DEBUG_BYTE [eax + FADT_ACPI_ENABLE]
		DEBUG_BYTE [eax + FADT_ACPI_DISABLE]
		call	newline
		DEBUG_DWORD [eax + FADT_PM1a_CNT_BLK_PORT],"PM1a CNT"
		DEBUG_DWORD [eax + FADT_PM1b_CNT_BLK_PORT], "PM1b CNT"
		DEBUG_BYTE [eax + FADT_PM1_CNT_LEN],"CNT LEN"
		call	newline

		DEBUG_DWORD [eax + FADT_PM1a_EVT_BLK_PORT],"PM1a EVT"
		DEBUG_DWORD [eax + FADT_PM1b_EVT_BLK_PORT], "PM1b EVT"
		DEBUG_BYTE [eax + FADT_PM1_EVT_LEN],"EVT LEN"
		call	newline



		DEBUG_DWORD [eax + FADT_PM1b_CNT_BLK_PORT], "PM2 CNT"
		call	newline
		DEBUG_WORD [eax + FADT_SCI_interrupt]

	.endif

	push	eax
	movzx	eax, word ptr [eax + FADT_SCI_interrupt]
	PIC_ENABLE_IRQ_LINE
	pop	eax

	.if 1
	pushad
	movzx	eax, byte ptr [eax + FADT_SCI_interrupt]
	mov	cx, cs
	mov	ebx, offset acpi_isr
	xor	edx, edx	# data arg for add_irq_handler/isr
	call	add_irq_handler
	popad
	.endif
	.if ACPI_DEBUG
		call	newline
	.endif

	# reference facp->dsdt (pointer to dsdt)

 	push	eax
	mov	eax, [eax + FADT_DSDT_ptr]
	add	eax, [acpi_addr_reloc$]
	.if ACPI_DEBUG
		DEBUG_DWORD eax,"DSDT"
	.endif
	ACPI_MAKE_SIG ebx, 'D','S','D','T'
	call	acpi_check_header$
	mov	edx, eax
	pop	eax
	jc	92f

	mov ebx, [edx]
	.if ACPI_DEBUG
		DEBUG "Found DSDT:"
		PRINTSIG
	.endif

	call	parse_dsdt$

	mov	ecx, [edx + acpi_tbl_size]
	add	edx, ACPI_TBL_HDR_SIZE # 36 # skip header
	.if ACPI_DEBUG
		DEBUG_DWORD ecx, "DSDT size"
	.endif
	sub	ecx, ACPI_TBL_HDR_SIZE # 36

	.if ACPI_DEBUG
		DEBUG "Finding _S5_"
	.endif

	# after the header (+36) the structure is AML.
	# manual scan for "_S5_":

	ACPI_MAKE_SIG ebx, '_', 'S', '5', '_'
0:	cmp	ebx, [edx]
	jz	2f
	inc	edx
	loop	0b
	jmp	92f
2:
	.if ACPI_DEBUG
		DEBUG "found _S5_";
	.endif

.if 1
	mov	esi, edx
# if ( ( *(S5Addr-1) == 0x08 || ( *(S5Addr-2) == 0x08 && *(S5Addr-1) == '\\') ) && *(S5Addr+4) == 0x12 )
# check for valid AML structure
#{
	mov	dl, [esi - 1]
	cmp	dl, 8
	jz	1f
	cmp	dl, '\''
	jnz	9f
	mov	al, [esi - 2]
	cmp	al, 8
	jnz	9f
	mov	al, [esi + 4]
	cmp	al, 0x12
	jnz	9f
1:
	.if ACPI_DEBUG
		PRINTLNc 0xf0 "Found valid AML structure"
	.endif
#S5Addr += 5;
#S5Addr += ((*S5Addr &0xC0)>>6) +2;   # calculate PkgLength size
	add	esi, 5
	mov	edx, esi
	and	edx, 0xc0
	sar	edx, 6
	add	edx, 2
	add	esi, edx

	cmp	[esi], byte ptr 0xa0 # skip byte pfx
	jnz	1f
	inc	esi
1:	mov	dx, [esi]
	shl	dx, 10
	mov	[SLP_TYPa], dx
	inc	esi

	cmp	[esi], byte ptr 0xa0	# 0xb0?
	jnz	1f
	inc	esi
1:	mov	dx, [esi]
	shl	dx, 10
	mov	[SLP_TYPb], dx

	PRINTc 3 " ACPI found"
	clc
9:	popad
	ret

.endif
91:	printlnc 4, "FACP->DSDT checksum error" # Label unused
	stc
	jmp	9b
92:	printlnc 4, "_S5_ not present"
	stc
	jmp	9b

# ACPIspec50.pdf section 5.4
# in: edx = dsdt ptr
parse_dsdt$:
	pushad
	mov	esi, edx
	mov	ecx, [esi + acpi_tbl_size]
	add	esi, ACPI_TBL_HDR_SIZE
	sub	ecx, ACPI_TBL_HDR_SIZE 
	mov	edi, esi	# backup
	mov	edx, ecx
	.if ACPI_DEBUG
		call	newline
		printc 11, "DSDT: size="
		call	printhex8
		call	newline

		push_ esi ecx
		.rept 3
		mov ecx, 0x8
	0:	lodsb
		call	printchar
		loop	0b
		mov	ecx, 8
		sub	esi, 8
	0:	call	printspace
		lodsb
		mov	dl, al
		call	printhex2
		loop	0b
		call	newline
		.endr
		pop_ ecx esi
	.endif

inc esi


0:	dec	ecx
	jle	9f

	mov	edx, esi
	sub	edx, edi
	.if ACPI_DEBUG
		call	printhex8
		print ": "
	.endif

	lodsb	# leadbyte
	mov	dl, al
	.if ACPI_DEBUG
		print "lead: "
		call	printhex2
		print " ("
		call	printbin8
		print ")"
	.endif

	# hi 2 bits = nr of bytes to follow for pkglen
	# 2 bits below that only used for 1-byte pkglen (maxlen 0x3f)
	# for 2 byte pkglen maxlen=0x0fff, 3: 0x0fffff, 4: 0x0f ffff ffff (?!)

	mov	eax, [esi - 1]
	and	al, 0b00111111

	shr	dl, 6	# hi 2 bits = nr of bytes for pkglen follow
	movzx	edx, dl
	.if ACPI_DEBUG
		DEBUG_BYTE dl
	.endif

	cmp	dl, 1
	jz	1f
	cmp	dl, 2
	jz	2f
	cmp	dl, 3
	jz	3f
	cmp	dl, 0
	jnz	5f
	and	eax, 0x3f
	jmp	4f
5:
	.if ACPI_DEBUG
		DEBUG_BYTE dl, "WARN: illegal value"
	.endif
	jmp	9f

# bytes follow:
3:	add	esi, 3
	shl	al, 4
	shr	eax, 4
	sub	ecx, 3
	jle	9f
	jmp	4f
2:	add	esi, 2
	and	eax, 0xffffff
	shl	al, 4
	shr	eax, 4
	sub	ecx, 2
	jle	9f
	jmp	4f
1:	inc	esi
	and	eax, 0xffff
	shl	al, 4
	shr	eax, 4
	sub	ecx, 1
	jle	9f
4:
## eax = pkglen
	mov	edx, eax
	.if ACPI_DEBUG
		print " pkglen: "
		call	printhex8

		call	printspace
		push eax
		mov eax, [esi]
		call	printchar; shr eax, 8
		call	printchar; shr eax, 8
		call	printchar; shr eax, 8
		call	printchar
		call	printspace
		pop eax
		mov	edx, [esi]
		call	printhex2; shr edx, 8
		call	printhex2; shr edx, 8
		call	printhex2; shr edx, 8
		call	printhex2
		call	printspace
		cmpw	[esi], '\\'
		jnz	1f
		printc 11, "ROOT"
	1:

		call	newline
	.endif

	or	eax, eax
	jle	9f

	add	esi, eax
	jmp	0b


9:
	popad
	ret


# checks for a given header and validates checksum
# in: eax = ptr to ACPI object, ebx = "ABCD" sig
# out: zf == cf : 1 = no match
acpi_check_header$:
	push_	eax ecx edx esi

#	PRINTc	0xf1 "Checking signature: "
#	PRINTSIG

	cmp	ebx, [eax]
	jnz	9f
	.if ACPI_DEBUG
		DEBUG "sig ok:"
		PRINTSIG
	.endif
0:
	mov	ecx, [eax+4] #assume size is 2 

	.if ACPI_DEBUG
		mov	edx, ecx
		print " size: "
		call	printhex8
	.endif

	push	esi
	mov	esi, eax
	xor	dx, dx
0:	lodsb
	add	dl, al
	loop	0b
	pop	esi

	.if ACPI_DEBUG
		DEBUG_BYTE dl, "checksum"
	.endif

	or	dl, dl
	jz	1f	# maybe with a cmc here somewhere...
9:	stc
1:	pop_	esi edx ecx eax
	ret



acpi_enable:
#	call	acpi_init
#	jc	no_acpi$

	mov	ebx, [acpi_fadt]

	mov	dx, [ebx + FADT_PM1a_CNT_BLK_PORT]
	in	ax, dx
	.if ACPI_DEBUG
		DEBUG_WORD dx, "PM1a control reg"
		DEBUG_WORD ax
	.endif
	or	ax, ax
	jz	0f

	PRINTLNc 4 "ACPI already enabled"
	jmp 0f # go on anyway

	clc
	ret
0:
	mov	dx, [ebx + FADT_SMI_CMD_PORT]
	mov	al, [ebx + FADT_ACPI_ENABLE]
	.if ACPI_DEBUG
		DEBUG_WORD dx,"SMI_CMD port"
		DEBUG_BYTE al,"ACPI_ENABLE"
		call	newline
	.endif
	or	dx, dx
	jz	0f
	or	al, al
	jz	0f
	PRINTc 3 "Enabling ACPI"
	mov	ah, al
	in	al, dx
	.if ACPI_DEBUG
		DEBUG_BYTE al,"SMI_CMD val"
		DEBUG_BYTE ah,"set val"
	.endif
	mov	al, ah
	out	dx, al

	mov ecx, 100
	10: in al, dx
	loop 10b

	.if ACPI_DEBUG
		DEBUG_BYTE al, "SMI_CMD val"
		call newline
	.endif


	# enable events
	mov	dx, [ebx + FADT_PM1a_EVT_BLK_PORT]
	.if ACPI_DEBUG
		DEBUG_WORD dx,"PM1a_EVT_BLK_PORT"
	.endif
	or	dx, dx
	jz	0f

	movzx	ax, byte ptr [ebx + FADT_PM1_EVT_LEN]
	.if ACPI_DEBUG
		DEBUG_WORD ax,"PM1 evt len"
	.endif
	shr	ax, 1
	add	dx, ax
	.if ACPI_DEBUG
		DEBUG_WORD dx, "PM1 ENABLE port"
	.endif

	PM1_EVT_TMR_EN=1<<0
	PM1_EVT_GBL_EN=1<<5 # global enable
	PM1_EVT_PWRBTN_EN=1<<8
	PM1_EVT_SLPBTN_EN=1<<9
	PM1_EVT_RCT_EN=1<<10#enable RTC_STS->wake
	PM1_EVT_PCIEXP_WAKE_DIS=1<<14
	in	ax, dx
	.if ACPI_DEBUG
		DEBUG_WORD ax, "PM1 evt val"
	.endif
	mov	ax, PM1_EVT_GBL_EN|PM1_EVT_PWRBTN_EN|PM1_EVT_SLPBTN_EN
	.if ACPI_DEBUG
		DEBUG_WORD ax,"set val"
	.endif
	out	dx, ax
	mov	ecx, 10
	10:
	in	ax, dx
	loop	10b
	.if ACPI_DEBUG
		DEBUG_WORD ax,"PM1_evt val"
	.endif


# need timer
	mov	dx, [ebx + FADT_PM1a_CNT_BLK_PORT]
	in	ax, dx
	.if ACPI_DEBUG
		DEBUG_WORD dx,"PM1a_CNT port"
		DEBUG_WORD ax
	.endif
	test	ax, PM1_SCI_EN#[ebx + SCI_EN]
	jnz	1f

	# optional
	mov	dx, [ebx + FADT_PM1b_CNT_BLK_PORT]
	.if ACPI_DEBUG
		DEBUG_WORD dx,"PM1b_CNT port"
		call	newline
	.endif
	or	dx, dx
	jz	1f
	in	ax, dx
	test	ax, PM1_SCI_EN#[ebx + SCI_EN]
	jnz	1f
	PRINTLNc 4 "Failed to initialize ACPI"
	stc
	ret
1: 	OK
	clc
	ret

0:	PRINTLNc 4 "not enough ACPI information to enable"
	stc
	ret




acpi_shutdown:
	PRINTLNc 0xf2 "ACPI shutdown"

cli
call paging_disable
#call paging_enable
#sti


#	push	ax
#	call	acpi_init
#	pop	ax
#	jc	no_acpi$

#	cmp	word ptr [SCI_EN], 0	# shutdown possibility
#	jz	no_acpi$
#
#	call	acpi_enable

	mov	ebx, [acpi_fadt]

	mov	dx, [ebx + FADT_PM1a_CNT_BLK_PORT]
	DEBUG_WORD dx,"PM1a port"
	mov	ax, [SLP_TYPa]
	or	ax, PM1_SLP_EN
	out	dx, ax
# possible shutdown may have occurred

	mov	dx, [ebx + FADT_PM1b_CNT_BLK_PORT]
	DEBUG_WORD dx,"PM1b port"
	or	dx, dx
	jz	0f
	mov	ax, [SLP_TYPb]
	or	ax, PM1_SLP_EN
	out	dx, ax
0:
	PRINTc	4, "ACPI Shutdown failure"
	ret

acpi_reboot:
	printc 0xf2, "ACPI reboot"
cli
call paging_disable
	mov	ebx, [acpi_fadt]
	DEBUG "reset:"
	# TODO: check FADT_flags & RESET_REGISTER
	DEBUG_BYTE [ebx + FADT_reset_reg + acpi_addr_space], "space"
	DEBUG_BYTE [ebx + FADT_reset_reg + acpi_addr_bitwidth], "bitw"	# 8
	DEBUG_BYTE [ebx + FADT_reset_reg + acpi_addr_bitoffs], "bitoffs" # 0
	DEBUG_BYTE [ebx + FADT_reset_reg + acpi_addr_xs_size], "xs_size"
	DEBUG_DWORD [ebx + FADT_reset_reg + acpi_addr_addr], "addr"
call paging_enable
sti

	ret

#.struct 0 # acpi_generic_address structure (GAS)
#acpi_addr_space:	.byte 0
#	# 0=system mem
#	# 1=system IO
#	# 2=pci config space
#	# 3=embedded controller
#	# 4=SMBus
#	# 5-0x7e reserved
#	# 0x7f=functional fixed hardware
#	# 0x80-0xbf reserved
#	# 0xc0-0xff OEM defined
#acpi_addr_bitwidth:	.byte 0
#acpi_addr_bitoffs:	.byte 0
#acpi_addr_xs_size:	.byte 0	# 0=undef; 1=byte,2=word;3=long;4=qword
#acpi_addr_addr:		.long 0, 0
#ACPI_GAS_SIZE = .



acpi_isr:
	push_	eax ebx edx ds es
	mov	ax, SEL_compatDS
	mov	ds, ax
	mov	es, ax

	DEBUG "ACPI ISR", 0xf4

	mov	ebx, [acpi_fadt]
call paging_disable
	mov	dx, [ebx + FADT_PM1a_EVT_BLK_PORT]	# status reg
	in	ax, dx
	DEBUG_WORD ax, "ACPI PM1 STS"
	PRINTFLAG ax, 1<<0, "TMR "
	PRINTFLAG ax, 1<<4, "BM "
	PRINTFLAG ax, 1<<5, "GBL "	# bios wants attention
	PRINTFLAG ax, 1<<8, "PWRBTN "
	PRINTFLAG ax, 1<<9, "SLPBTN "
	PRINTFLAG ax, 1<<10, "RTC "
	PRINTFLAG ax, 1<<14, "PCIEXP_WAKE "
	PRINTFLAG ax, 1<<15, "WAKE "

	PIC_SEND_EOI [ebx + FADT_SCI_interrupt]
call paging_enable
	pop_	es ds edx ebx eax
	iret
