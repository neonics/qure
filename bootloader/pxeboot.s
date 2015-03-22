# The BootSector
#
# Includes sector1, determines size, and loads it using the MBR data.
.intel_syntax noprefix

# Layout:
# 0000-0200: sector 0. Only .text used. subsections/.data prohibited.
# 0200-....: all allowed.

RELOCATE=1	# 0 doesn't work
WHITE_PRESSKEY=0

#######################################################
COLOR_BG	= 0x07
COLOR_TITLE	= 0x0b
COLOR_LABEL	= 0x07
COLOR_ERROR	= 0x04
COLOR_DATA	= 0x08
COLOR_SUCCESS	= 0x02
COLOR_OK	= 0x0a

.text
.code16

# in: cs:ip = 0000:7c00
# in: es:bx = PXENV+ ptr (deprecated)
# in: ss:sp = usable stack, min 1.5kb
# in: ss:[sp+4] = far ptr to !PXE struct
black:
######## fix cs:ip
	call	1f
1:	pop	dx
	sub	dx, offset 1b
	shr	dx, 4	# assume we are loaded on a 16 byte boundary
	push	dx
	push	offset 1f
	retf
1:
#######
	# disable cursor
	mov	cx, 0x2000	# 0x2607 - underline rows 6 and 7
	mov	ah, 1
	int	0x10

	mov	dx, es

	# init screen
	mov	ax, 0x0f00
	call	cls		# init es:di

	call	printhex	# es:bx: PXENV+ (same as int 1ah)
	sub	di, 2
	mov	al, ':'
	stosw
	mov	dx, bx
	call	printhex

	mov	dx, cs
	call	printhex	# 0000
	mov	dx, ds
	call	printhex	# 9300
	mov	dx, ss
	call	printhex	# 9280
	mov	dx, sp
	call	printhex	# 0768
	# ss:sp = 9280:0768
	# cs:ip = 0000:7c00
	# ds = 9300

	mov	ax, cs
	mov	ds, ax

	mov	ah, 11
	mov	dx, 0x1337
	call	printhex
	mov	ah, COLOR_BG

	push	bp	# bp must be preserved or retf fails.
	mov	bp, sp
	add	bp, 2
	mov	dx, bp
	inc	ah
	call	printhex
	dec	ah
	mov	dx, ss:[bp]
	call	printhex
	mov	dx, ss:[bp+2]
	call	printhex
	mov	dx, ss:[bp+4]
	call	printhex
	mov	dx, ss:[bp+6]
	call	printhex
	pop	bp

	call	newline
	call	printregisters

	
	call	pxe

	#PRINT "Returning to BIOS"
	.data
	109: .asciz "Returning to BIOS "
	.text
	mov	si, offset 109b
	call	print

	mov	ax, PXENV_STATUS_SUCCESS	# remove both
	#mov	ax, PXENV_STATUS_KEEP_UNDI	# remove base code, keep undi
	mov	ax, PXENV_STATUS_KEEP_ALL	# keep both
	retf


halt:	hlt
	jmp	halt

bkp_cs$:.word 0
bkp_ds$:.word 0
bkp_ss$:.word 0
bkp_sp$:.word 0


fail:	push	ax
	push	dx
	push	ax		# save bios result code
	mov	ah, COLOR_ERROR 
	mov	dx, 0xfa11
	call	printhex
	mov	ah, COLOR_DATA
	pop	dx		# restore bios result code
	call	printhex
	pop	dx
	pop	ax

	call	printregisters
	.if 0
		movw	es:[di], 'R'|(0xf4<<8)
		mov	dx, 0x40
		mov	fs, dx
		mov	ah, 0xf0
		mov	dx, fs:[0x6c]	# BDA daily timer (dword) - TODO timeout reboot
		call	printhex

		xor	ah,ah
		int	0x16
		ljmp	0xffff,0
	.else
		jmp	halt
	.endif


.if 0
	# ss:sp points to the end of the first sector.
	mov	cs:[sp_bkp$], sp
		# backup sp
		#mov	sp, 512	# make it so, regardless of bios
		#mov	cs:[ss_bkp$], ss
		.if 1
		# have the stack before cs:0000
		mov	sp, cs
		sub	sp, 65536 >> 4
		mov	ss, sp
		mov	sp, 0xfffe	# word alignment
		.else
		# set up stack at cs:0xF000
		mov	sp, cs
		mov	ss, sp
		mov	sp, 512	# use the 0xaa55 signature
		call	0f
	0:	pop	sp
		and	sp, ~0xff
		add	sp, 0xF000 + (CODE_SIZE - black) & ~ 0xff
		.endif
		call	init
	0:
.endif

sp_bkp$: .word 0


.if 0
	###################################################################
	relocate$:

	.if RELOCATE
	LOAD_ADDR = 0x10000
	LOAD_SEG =  (LOAD_ADDR >> 4 )
	LOAD_OFFS= 0 # the base address (16 bit offset) for which the binary is coded

		mov	di, cs
		mov	ds, di
		mov	di, LOAD_SEG
		mov	es, di
		#mov	ds, di
		mov	di, LOAD_OFFS
		call	0f
	0:	pop	si
		sub	si, 0b - black
		mov	cx, CODE_SIZE # 512 // we don't load succeeding sectors
		rep	movsb
		jmp	LOAD_SEG, (offset 0f) + LOAD_OFFS
	0:
	.endif
	###################################################################

	############################################################################
	.if WHITE_PRESSKEY
	msg_presskey$: .asciz "Press Key"
	.endif
	# stack setup at 0:0x9c00
	# sp is 32 bytes below that, pointing to the registers starting
	# with ip, the return address of the 1337 loader, which then simply
	# halts.
	white: 	
		#cli
	.if WHITE_PRESSKEY
		mov	si, offset msg_presskey$
		call	print
		xor	ah, ah
		int	0x16
	.endif
		# bp = sp = saved registers ( 9BE0; top: 9C00 = 7C00 + 2000 )

		mov	ax, 0xf000
		call	cls	# side effect: set up es:di to b800:0000

	.if 0
		mov	ah, 0xf4

		mov	dx, sp
		call	printhex
		mov	dx, bp
		call	printhex

		mov	dx, offset CODE_SIZE	# 268h
		call	printhex

	     rainbow$:
		call	newline
		mov	ax, 0x00 << 8 | 254
		mov	cx, 4
	1:	push	cx
		mov	cx, 256 / 4
	0:	stosw
		inc	ah
		loop	0b
		pop	cx
		call	newline
		loop	1b

		call	printregisters
	.endif
		mov	ah, 0xf8
		mov	dx, [bp+24]	# load dx - boot drive
		call	printhex

		mov	al, '!'
		stosw
		mov	dx, 0xabcd
		call	printhex
		jmp 	sector1$



	BOOTSECTOR=1
	.include "../16/print.s"
	BOOTSECTOR = 0
	############################################################################
	. = 512
	sector1$:
	mov ax, 0x0720
	call cls
	#xor di,di
	mov al, '-'
	mov ah, 0xf0
	stosw
	0:hlt;jmp 0b
	#.include "pxeboot.s"


.endif

	##################
	BOOTSECTOR=1
	.include "../16/print.s"
	SECTOR1=1
	BOOTSECTOR=0
	.include "../16/print.s"



####################################
DEBUG_BOOTLOADER = 0	# 0: no keypress. 1: keypress; 2: print ramdisk/kernel bytes.
CHS_DEBUG = 0
RELOC_DEBUG = 0		# 0: no debug; 1: debug; 2: keypress

MULTISECTOR_LOADING = 1	# 0: 1 sector, 1: 128 sectors(64kb) at a time
KERNEL_ALIGN_PAGE = 1	# load kernel at page boundary
KERNEL_RELOCATION = 1

TRACE_RELOC_ADDR = 0	# trace zero-based kernel image offset; 0 = no trace

KERNEL_IMG_PARTITION = 0 # 1: first bootable partition; 0: img follows bootloader

.text
.code16
#. = 512
.data
bootloader_registers: .space 32

msg_sector1$: .asciz "Transcended sector limitation!"
.text
#mov	ax, 0xf000
#call	cls
mov ax, (0xf0 << 8) | '?'
stosw
.rept 7
inc	ah
stosw
.endr
0:hlt; jmp 0b
	# copy bootloader registers
.if 0
	push	es
	push	ds
	push	di
	push	si
	push	cx

	push	ds
	pop	es

	push	ss	# copy from stack
	pop	ds

	mov	si, bp
	mov	di, offset bootloader_registers
	mov	cx, 32 / 4
	rep	movsd

	pop	cx
	pop	si
	pop	di
	pop	ds
	pop	es
.endif
	mov	ax, 0x0720
#call cls

#mov dx, cs; call	printhex
#mov dx, ds; call printhex
#mov dx, es; call printhex
#mov dx, ss; call printhex

	mov	si, offset msg_sector1$
mov dx, si
call printhex
	call	print
mov al, '.'
	stosw
.if 1
	mov	edx, [bootloader_sig]
	call	printhex8
	call	newline
.endif
#0:hlt; jmp 0b
	jmp	main

main:
	
################### PXE
.struct 0
pxenv_sig:		.space 6 # "PXENV+"
pxenv_version:		.word 0	# 0x0201
pxenv_len:		.byte 0
pxenv_chksum:		.byte 0
pxenv_rmentry:		.long 0	# far ptr: off,seg
pxenv_pmoffs:		.long 0	# 32 bit offset - do not use
pxenv_pmsel:		.word 0	# selector - do not use
pxenv_stackseg:		.word 0	# stack segment
pxenv_stacksize:	.word 0	# stack size
pxenv_bccodeseg:	.word 0	# BC
pxenv_bccodesize:	.word 0
pxenv_bcdataseg:	.word 0	
pxenv_bcdatasize:	.word 0
pxenv_udataseg:		.word 0	# UNDI
pxenv_udatasize:	.word 0
pxenv_ucodeseg:		.word 0	
pxenv_ucodesize:	.word 0
pxenv_pxeptr:		.long 0	# far ptr: offs, seg
.data
pxenv:	.word 0, 0	# name must match struct prefix
pxeplus:.word 0, 0	# name must match struct prefix
pxenv_api:	.word 0, 0	# api far ptr; offset must be 0
pxeplus_api:	.word 0, 0	# api far ptr
.text
pxe:
	push	es
	mov	ax, 0x5650
	int	0x1a	# out: ax=0x564e, es:bx='PXENV+' structure; edx=trashed
	mov	[pxenv + 2], es
	mov	[pxenv + 0], bx
	pop	es
	cmp	ax, 0x564e
	jz	1f

	mov	ah, COLOR_ERROR
	PRINT	"PXE not detected"
	jmp	fail

1:	mov	ah, COLOR_SUCCESS
	PRINT "PXE detected "
	mov	ah, COLOR_DATA
	mov	si, offset pxenv
	call	_print_farptr$

	# print structure
	mov	ah, COLOR_LABEL	# 0xf1
	lfs	si, [pxenv]
	mov	cl, fs:[si + pxenv_len]
	call	_pxe_checksum$
	mov	dx, fs:[si + pxenv_rmentry+0]
	mov	[pxenv_api + 0], dx
	mov	dx, fs:[si + pxenv_rmentry+2]
	mov	[pxenv_api + 2], dx
	call	_pxe_printenv$

	call	_pxe_detect_plus$
	lfs	si, [pxeplus]
	mov	dx, fs:[si + pxeplus_rmentry+0]
	mov	[pxeplus_api + 0], dx
	mov	dx, fs:[si + pxeplus_rmentry+2]
	mov	[pxeplus_api + 2], dx

#ret

	mov	ax, 0x0720
	call	cls

	print "Doing API call to fs:si"
	lfs	si, [pxeplus_api]
	call	printregisters
	# we'll assume pxeplus is setup.

	call	pxe_get_cached_info
	call	pxe_tftp_open
	jmp	halt
	ret


.data
tftp_open:
tftp_open_status:	.word 0
tftp_open_server_ip:	.long 192,168,1,2
tftp_open_gw_ip:	.long 192,168,1,1
tftp_open_filename:	.asciz "/boot/kernel.img"
.space 128 - (.-tftp_open_filename)
tftp_open_tftp_port:	.word 69 << 8
tftp_open_packetsize:	.word 512
.text

pxe_tftp_open:
	push	ds
	push	offset tftp_open
	push	PXENV_TFTP_OPEN
	lcall	[pxeplus_api]
	add	sp, 6

	call printregisters

	printc COLOR_TITLE, "API RET: "
	mov	dx, ax
	mov	ah, COLOR_BG
	call	printhex

	mov	si, offset tftp_open
	printc COLOR_LABEL, "Status: "
	lodsw; mov dx, ax; mov ah, COLOR_DATA; call printhex2
	call	_nl_indent$


	ret



pxe_get_cached_info:
	mov	dx, offset packet
	mov	[pxenv_get_cached_info_bufaddr+0], dx
	mov	[pxenv_get_cached_info_bufaddr+2], cs
	movw	[pxenv_get_cached_info_bufsize], 1500
	movw	[pxenv_get_cached_info_buflimit], 1500
	movw	[pxenv_get_cached_info_pkt_type], 2

	push	ds
	push	offset pxenv_get_cached_info
	push	PXENV_GET_CACHED_INFO		# 0x0071
	lcall	[pxeplus_api]
	add	sp, 6

#mov ax, 0x0720
#call cls
call printregisters

	printc COLOR_TITLE, "API RET: "
	mov	dx, ax
	mov	ah, COLOR_BG
	call	printhex


	mov	si, offset pxenv_get_cached_info
	printc COLOR_LABEL, "Status: "
	lodsw; mov dx, ax; mov ah, COLOR_DATA; call printhex2
	call	_nl_indent$

	printc COLOR_LABEL, "PktType: "
	lodsw; mov dx, ax; mov ah, COLOR_DATA; call printhex
	printc COLOR_LABEL, "BufSize: "
	lodsw; mov dx, ax; mov ah, COLOR_DATA; call printhex
	printc COLOR_LABEL, "Buffer: "
	mov	dx, [si + 2]; call printhex
	sub di, 2; PRINTCHAR ':'
	mov	dx, [si + 0]; call printhex
	add	si, 4
	printc COLOR_LABEL, "Buf Lim: "
	lodsw; mov dx, ax; mov ah, COLOR_DATA; call printhex
	call	newline
	ret
.data
pxenv_get_cached_info:
pxenv_get_cached_info_status:	.word 0	# status
pxenv_get_cached_info_pkt_type: .word 3	# packet_type: cached reply
pxenv_get_cached_info_bufsize:	.word 0	# buffersize
pxenv_get_cached_info_bufaddr:	.long 0	# far ptr
pxenv_get_cached_info_buflimit:	.word 0
packet: .space 1530
.text


_pxe_printenv$:
	mov	ax, COLOR_DATA << 8 | ' '

	lfs	si, [pxenv]

	.rept 6
	mov	al, fs:[si]
	stosw	#printchar	# "PXENV+"
	inc	si
	.endr
	mov	al, ' '; stosw
	sub	si, 6

	PRINTCHAR 'v'
	mov	dx, fs:[si + pxenv_version]
	add	si, 2
	call	printhex	# version
	# if version 2.1  (dx=0x0201) then PXE+ (pmode etc)

	call	_nl_indent$

	mov	ah, COLOR_DATA

	.macro PXE_PRINT_FARPTR which, field, label
		PRINTC COLOR_TITLE, "\label "
		lfs	si, [\which]
		add	si, offset \which\()_\field
		call	_pxe_print_farptr$
	.endm

	.macro PXE_PRINT_LONG which, field, label
		PRINTC COLOR_TITLE, "\label "
		lfs	si, [\which]
		mov	edx, fs:[si + \which\()_\field]
		call	printhex8
	.endm


	.macro PXE_PRINT_WORD which, field, label
		PRINTC COLOR_TITLE, "\label "
		lfs	si, [pxenv]
		lfs	si, [\which]
		mov	dx, fs:[si + \which\()_\field]
		call	printhex
	.endm

	.macro PXE_PRINT_SEGSIZE which, field, label=0
		.ifnc \label,0
		PRINTC COLOR_TITLE, "\label "
		.else
		PRINTC COLOR_TITLE, "\field "
		.endif
		lfs	si, [\which]
		mov	dx, fs:[si + \which\()_\field\()seg]
		call	printhex
		mov	dx, fs:[si + \which\()_\field\()size]
		call	printhex
	.endm



	PXE_PRINT_FARPTR pxenv rmentry, "RM"
	PXE_PRINT_LONG pxenv pmoffs, "PM"
	PXE_PRINT_WORD pxenv pmsel, "sel"

	call	_nl_indent$

	PXE_PRINT_SEGSIZE pxenv stack
	PXE_PRINT_SEGSIZE pxenv bccode
	PXE_PRINT_SEGSIZE pxenv bcdata

	call	_nl_indent$

	PXE_PRINT_SEGSIZE pxenv udata "UNDI data"
	PXE_PRINT_SEGSIZE pxenv ucode "UNDI code"

	PXE_PRINT_FARPTR pxenv pxeptr, "PXE ptr"
	call	newline
	ret


.struct 0
pxeplus_sig:		.long 0	# "!PXE"
pxeplus_len:		.byte 0
pxeplus_cksum:		.byte 0
pxeplus_rev:		.byte 0	# revision 0
pxeplus_res:		.byte 0	# reserved, must be 0
pxeplus_undirom:	.long 0	# UNDI ROM ID far ptr
pxeplus_baserom:	.long 0	# UNDI ROM ID far ptr
pxeplus_rmentry:	.long 0	# far ptr
pxeplus_pmentry:	.long 0	# far ptr
pxeplus_statusco:	.long 0 # far ptr to DHCP/TFTP status callout
pxeplus_res2:		.byte 0	# reserved, must be 0
pxeplus_nsegdesc:	.byte 0	# number of segment descriptors (4..7)
pxeplus_sel0:		.word 0	# first PM selector (rest is consecutive)
pxeplus_sel_stack:	.space 8	# .word seg; .long linptr; .word size
pxeplus_sel_udata:	.space 8	# .word seg; .long linptr; .word size
pxeplus_sel_ucodero:	.space 8	# .word seg; .long linptr; .word size
pxeplus_sel_ucoderw:	.space 8	# .word seg; .long linptr; .word size
pxeplus_sel_bcdata:	.space 8	# .word seg; .long linptr; .word size
pxeplus_sel_bccodero:	.space 8	# .word seg; .long linptr; .word size
pxeplus_sel_bccoderw:	.space 8	# .word seg; .long linptr; .word size
.text
	.macro PXE_PRINT_DESC which, field, label=0
		.ifnc \label,0
		PRINTc COLOR_TITLE "\label "
		.else
		PRINTc COLOR_TITLE "\field "
		.endif
		PRINTc COLOR_LABEL "seg "
		mov	dx, fs:[si + \which\()_sel_\field + 0]
		call	printhex
		PRINTc COLOR_LABEL "offs "
		mov	edx, fs:[si + \which\()_sel_\field + 2]
		call	printhex8
		PRINTc COLOR_LABEL "size "
		mov	dx, fs:[si + \which\()_sel_\field + 6]
		call	printhex
	.endm

_pxe_detect_plus$:
	PRINTc COLOR_LABEL, "!PXE "

	lfs	si, [pxenv]
	mov	dx, fs:[si + pxenv_version]
	cmp	dx, 0x0201
	jb	91f

	mov	edx, fs:[si + pxenv_pxeptr]
	mov	[pxeplus], edx

	lfs	si, [pxeplus]
	mov	edx, fs:[si]		# get "!PXE" signature
	cmp	edx, ('!'<<0)|('P'<<8)|('X'<<16)|('E'<<24)
	jnz	91f


	lfs	si, [pxeplus]
	mov	cl, fs:[si + pxeplus_len]
	call	_pxe_checksum$
	call	_nl_indent$

	PXE_PRINT_FARPTR pxeplus undirom, "UNDI ROM"
	PXE_PRINT_FARPTR pxeplus baserom, "BASE ROM"
	PXE_PRINT_FARPTR pxeplus rmentry, "RM Entry"
	PXE_PRINT_FARPTR pxeplus pmentry, "PM Entry"
	call	_nl_indent$

	PXE_PRINT_FARPTR pxeplus statusco, "Status Callout"

	PXE_PRINT_WORD pxeplus nsegdesc, "num_sel"
	PXE_PRINT_WORD pxeplus sel0, "sel0"
	call	_nl_indent$

	PXE_PRINT_DESC pxeplus stack	"Stack        "
	call	_nl_indent$
	PXE_PRINT_DESC pxeplus udata	"UNDI Data    "
	call	_nl_indent$
	PXE_PRINT_DESC pxeplus ucodero	"UNDI Code(ro)"
	call	_nl_indent$
	PXE_PRINT_DESC pxeplus ucoderw	"UNDI Code(ro)"
	call	_nl_indent$
	PXE_PRINT_DESC pxeplus bcdata	"BC   Data    "
	call	_nl_indent$
	PXE_PRINT_DESC pxeplus bccodero	"BC   Code(ro)"
	call	_nl_indent$
	PXE_PRINT_DESC pxeplus bccoderw	"BC   Code(rw)"


	jmp	newline

91:	PRINTc COLOR_ERROR "not found; using PXENV+"
	ret


########################## API
PXENV_UNLOAD_STACK		= 0x0070
	# out: { .word PXENV_STATUS_*; reserved: .space 10 }
PXENV_GET_CACHED_INFO		= 0x0071
	# .word PXENV_STATUS;	# (out)
	# .word packettype	# (in) 1=DHCP_DISCOVER, 2=DHCP_ACK; 3=CACHED_REPLY
	# .word bufsize		# (in/out)
	# .long buffer		# (in/out) far ptr
	# .word buflimit	# (out) BC dataseg max buf size
PXENV_RESTART_TFTP		= 0x0073
PXENV_START_UNDI		= 0x0000	# called during option rom boot; inits int 0x1a
PXENV_STOP_UNDI			= 0x0015	# unhooks int 0x1a

PXENV_START_BASE		= 0x0075
PXENV_STOP_BASE			= 0x0076


PXENV_TFTP_OPEN			= 0x0020 # in: see tftp_open_param
PXENV_TFTP_CLOSE		= 0x0021 # in: see tftp_open_param
PXENV_TFTP_READ			= 0x0022 # reads 1 packet
PXENV_TFTP_READ_FILE		= 0x0023 # 
PXENV_TFTP_GET_FSIZE		= 0x0025

PXENV_UDP_OPEN			= 0x0030
PXENV_UDP_CLOSE			= 0x0031
PXENV_UDP_READ			= 0x0032
PXENV_UDP_WRITE			= 0x0033

PXENV_UNDI_STARTUP		= 0x0001
PXENV_UNDI_CLEANUP		= 0x0002
PXENV_UNDI_INIT			= 0x0003
PXENV_UNDI_RESET_NIC		= 0x0004
PXENV_UNDI_SHUTDOWN		= 0x0005
PXENV_UNDI_OPEN			= 0x0006
PXENV_UNDI_CLOSE		= 0x0007
PXENV_UNDI_XMIT			= 0x0008	# send packet
PXENV_UNDI_SET_MCAST_ADDR	= 0x0009
PXENV_UNDI_SET_STATION_ADDR	= 0x000a	# sets MAC
PXENV_UNDI_SET_PACKET_FILTER	= 0x000b
PXENV_UNDI_GET_INFO		= 0x000c
	# out:
	# .word status
	# .word base_io
	# .word int_nr
	# .word max_tx_unit
	# .word hw_type	# 1=ethernet, 2=exp ether, 6=IEEE, 7=ACRNET
	# .word hw_addr_len
	# .space 6	# current MAC addr
	# .space 6	# permanent/hw MAC addr
	# .word 0	# RM ROM segment
	# .word 0	# rx queue len
	# .word 0	# tx queue len
PXENV_UNDI_GET_STATS		= 0x000d
	# .word status; .long tx_good, rx_good, rx_err, rx_dropped_queue_full
PXENV_UNDI_CLEAR_STATS		= 0x000e
PXENV_UNDI_INIT_DIAGNOSTICS	= 0x000f
PXENV_UNDI_FORCE_INTERRUPT	= 0x0010
PXENV_UNDI_GET_MCAST_ADDR	= 0x0011
PXENV_UNDI_GET_NIC_TYPE		= 0x0012
PXENV_UNDI_GET_IFACE_INFO	= 0x0013
PXENV_UNDI_ISR			= 0x0014
PXENV_UNDI_GET_STATE		= 0x0015
	# out: .word status; .byte state	# 1=started; 2= initialized; 3=opened


# ax responses:
PXENV_EXIT_SUCCESS		= 0x0000
PXENV_EXIT_FAILURE		= 0x0001

# Status
PXENV_STATUS_SUCCESS			= 0x00
PXENV_STATUS_FAILURE			= 0x01
PXENV_STATUS_BAD_FUNC			= 0x02
PXENV_STATUS_UNSUPPORTED		= 0x03
PXENV_STATUS_KEEP_UNDI			= 0x04
PXENV_STATUS_KEEP_ALL			= 0x05
PXENV_STATUS_OUT_OF_RESOURCES		= 0x06
PXENV_STATUS_ARP_TIMEOUT		= 0x11	# arp errors 0x10-0x1f
PXENV_STATUS_UDP_CLOSED			= 0x18
PXENV_STATUS_UDP_OPEN			= 0x19
PXENV_STATUS_TFTP_CLOSED		= 0x1a
PXENV_STATUS_TFTP_OPEN			= 0x1b
PXENV_STATUS_MCOPY_PROBLEM		= 0x20	# BIOS/system errors 0x20-0x2f
PXENV_STATUS_BIS_INTEGRITY_FAILURE	= 0x21
PXENV_STATUS_BIS_VALIDATE_FAILURE	= 0x22
PXENV_STATUS_BIS_INIT_FAILURE		= 0x23
PXENV_STATUS_BIS_SHUTDOWN_FAILURE	= 0x24
PXENV_STATUS_BIS_GBOA_FAILURE		= 0x25
PXENV_STATUS_BIS_FREE_FAILURE		= 0x26
PXENV_STATUS_BIS_GSI_FAILURE		= 0x27
PXENV_STATUS_BIS_BAD_CKSUM		= 0x28

PXENV_STATUS_TFTP_ARP_ERROR		= 0x30	# 'CANNOT_ARP_ADDRESS'; TFTP/MTFTP errors 0x30-0x3f
PXENV_STATUS_TFTP_OPEN_TIMEOUT		= 0x32


PXENV_STATUS_TFTP_UNKNOWN_OPCODE	= 0x33
PXENV_STATUS_TFTP_READ_TIMEOUT		= 0x35
PXENV_STATUS_TFTP_ERROR_OPCODE		= 0x36
PXENV_STATUS_TFTP_CANNOT_OPEN_CONNECTION= 0x38
PXENV_STATUS_TFTP_CANNOT_READ_FROM_CONNECTION= 0x39
PXENV_STATUS_TFTP_TOO_MANY_PACKAGES	= 0x3A
PXENV_STATUS_TFTP_FILE_NOT_FOUND	= 0x3B
PXENV_STATUS_TFTP_ACCESS_VIOLATION	= 0x3C
PXENV_STATUS_TFTP_NO_MCAST_ADDRESS	= 0x3D
PXENV_STATUS_TFTP_NO_FILESIZE		= 0x3E
PXENV_STATUS_TFTP_INVALID_PACKET_SIZE	= 0x3F
# Reserved errors 0x40-0x4f
# DHCP/BOOTP errors 0x50-0x5f
PXENV_STATUS_DHCP_TIMEOUT		= 0x51
PXENV_STATUS_DHCP_NO_IP_ADDRESS		= 0x52
PXENV_STATUS_DHCP_NO_BOOTFILE_NAME	= 0x53
PXENV_STATUS_DHCP_BAD_IP_ADDRESS	= 0x54
/* Driver errors (0x60 to	= 0x6F) */
/* These errors are for UNDI compatible NIC drivers. */
PXENV_STATUS_UNDI_INVALID_FUNCTION	= 0x60
PXENV_STATUS_UNDI_MEDIATEST_FAILED	= 0x61
PXENV_STATUS_UNDI_CANNOT_INIT_NIC_FOR_MCAST= 0x62
PXENV_STATUS_UNDI_CANNOT_INITIALIZE_NIC	= 0x63
PXENV_STATUS_UNDI_CANNOT_INITIALIZE_PHY	= 0x64
PXENV_STATUS_UNDI_CANNOT_READ_CONFIG_DATA=0x65
PXENV_STATUS_UNDI_CANNOT_READ_INIT_DATA	= 0x66
PXENV_STATUS_UNDI_BAD_MAC_ADDRESS	= 0x67
PXENV_STATUS_UNDI_BAD_EEPROM_CHECKSUM	= 0x68
PXENV_STATUS_UNDI_ERROR_SETTING_ISR	= 0x69
PXENV_STATUS_UNDI_INVALID_STATE		= 0x6A
PXENV_STATUS_UNDI_TRANSMIT_ERROR	= 0x6B
PXENV_STATUS_UNDI_INVALID_PARAMETER	= 0x6C
/* ROM and NBP Bootstrap errors (0x70 - 0x7F) */
PXENV_STATUS_BSTRAP_PROMPT_MENU		= 0x74
PXENV_STATUS_BSTRAP_MCAST_ADDE		= 0x76
PXENV_STATUS_BSTRAP_MISSING_LIST	= 0x77
PXENV_STATUS_BSTRAP_NO_RESPONSE		= 0x78
PXENV_STATUS_BSTRAP_FILE_TOO_BIG	= 0x79
/* Environment NBP errors (0x80 - 0x8F) */
/* Reserved errors (0x90 to 0x9F) */
/* Misc. errors (0xA0 to 0xAF) */
PXENV_STATUS_BINL_CANCELED_BY_KEYSTROKE	= 0xA0
PXENV_STATUS_BINL_NO_PXE_SERVER		= 0xA1
PXENV_STATUS_NOT_AVAILABLE_IN_PMODE	= 0xA2
PXENV_STATUS_NOT_AVAILABLE_IN_RMODE	= 0xA3
/* BUSD errors (0xB0 - 0xBF) */
PXENV_STATUS_BUSD_DEVICE_NOT_SUPPORTED	= 0xB0
/* Loader errors (0xC0 - 0xCF) */
PXENV_STATUS_LOADER_NO_FREE_BASE_MEMORY	= 0xC0
PXENV_STATUS_LOADER_NO_BC_ROMID		= 0xC1
PXENV_STATUS_LOADER_BAD_BC_ROMID	= 0xC2
PXENV_STATUS_LOADER_BAD_BC_RUNTIME_IMAGE= 0xC3
PXENV_STATUS_LOADER_NO_UNDI_ROMID	= 0xC4
PXENV_STATUS_LOADER_BAD_UNDI_ROMID	= 0xC5
PXENV_STATUS_LOADER_BAD_UNDI_DRIVER_IMAGE=0xC6
PXENV_STATUS_LOADER_NO_PXE_STRUCT	= 0xC8
PXENV_STATUS_LOADER_NO_PXENV_STRUCT	= 0xC9
PXENV_STATUS_LOADER_UNDI_START		= 0xCA
PXENV_STATUS_LOADER_BC_START		= 0xCB
# Vendor errors (0xD0 - 0xFF)


.data
tftp_open_param:
tftp_open_param_status:		.word 0
tftp_open_param_server_ip:	.long 0
tftp_open_param_gw_ip:		.long 0
tftp_open_param_filename:	.space 128
tftp_open_param_tftp_port:	.word 69 << 8
tftp_open_param_packetsize:	.word 512

.text
pxenv_api_call:
	push	es
		lfs si, [pxenv]
		# es:di -> tftp_open_param
		push	ds
		pop	es
		mov	di, offset tftp_open_param

		lcall fs:[si + pxenv_rmentry]	# call pxenv_undicode, 0
	pop	es
	ret

pxeplus_api_call:
	push	ds
	push	offset tftp_open_param
	push	PXENV_TFTP_OPEN
	lfs	si, [pxeplus]
	lcall	fs:[si + pxeplus_rmentry]
	add	sp, 6
	ret
##########################



# in: fs:si = struct start
# in: cl = struct len
_pxe_checksum$:
	xor	ch, ch

	push	ds
	push	si
	push	fs
	pop	ds
	xor	dl, dl
0:	lodsb
	add	dl, al
	loop	0b
	pop	si
	pop	ds

	push	ax
	mov	ah, COLOR_LABEL
	PRINT "checksum "
	mov	ah, COLOR_DATA
	call	printhex2	# the actual checksum
	pop	ax
	or	dl, dl
	jnz	fail

	sub	di, 2
	call	_ok$
	mov	al, ' '
	stosw
	ret


_pc$:
	dec	ah
	stosw
	mov	al, '='
	stosw
	inc	ah
	ret

_ok_nl$:
	call	_ok$
	jmp	newline
	
_ok$:	push	ax
	mov	ax, COLOR_OK << 8 | ' '
	stosw
	mov	al, 'O'
	stosw
	mov	al, 'K'
	stosw
	pop	ax
	ret

_nl_indent$:
	call	newline
	mov	al, ' '
	stosw
	stosw
	ret

# in: si = mem address of far pointer (si[0] = offs, si[2]=seg)
_print_farptr$:
	mov	dx, [si + 2]
	call	printhex
	mov	al, ':'
	sub	di, 2
	stosw	# printchar
	mov	dx, [si + 0]
	call	printhex
	ret

_pxe_print_farptr$:
	mov	dx, fs
	push	ds
	mov	ds, dx
	call	_print_farptr$
	pop	ds
	ret

###################
###################################################
.include "../16/waitkey.s"
.include "../16/printregisters.s"

.data
bootloader_sig: .long 0x1337c0de
####################################

.data	# we need the entire size, including data! .data after .code..
.equ CODE_SIZE, .
