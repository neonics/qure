##############################################################################
## VMWare interface
#
# open-vm-tools/lib/include/backdoor_def.h, lib/rpcIn etc.
.intel_syntax noprefix

VMWARE_DEBUG = 1

VMWARE_DISABLE_HB = 1	# disable high bandwidth (rep insb/outsb)

# 'Backdoor' access: on read/write from special ports, having eax contain
# a magic number, the VM steps in and treats the IO access as a backdoor call.

VMWARE_BD_PORT = 0x5658	# "VX" (reverse)
VMWARE_BD_MAGIC = 0x564d5868 # "VMXh" (reverse)

# These go in cx
VMWARE_BD_CMD_GET_MHZ			= 1
VMWARE_BD_CMD_APM_FUNCTION		= 2
VMWARE_BD_CMD_GET_DISK_GEO		= 3
VMWARE_BD_CMD_GET_PTR_LOCATION		= 4
VMWARE_BD_CMD_SET_PTR_LOCATION		= 5
VMWARE_BD_CMD_GET_SEL_LENGTH		= 6 # copy..
VMWARE_BD_CMD_GET_NEXT_PIECE		= 7 # ..and..
VMWARE_BD_CMD_SET_SEL_LENGTH		= 8 # ..paste
VMWARE_BD_CMD_GET_VERSION		= 10
VMWARE_BD_CMD_GET_DEVICELISTELEMENT	= 11
VMWARE_BD_CMD_TOGGLED_EVICE		= 12
VMWARE_BD_CMD_GET_GUI_OPTIONS		= 13
VMWARE_BD_CMD_SET_GUI_OPTIONS		= 14
VMWARE_BD_CMD_GET_SCREEN_SIZE		= 15
VMWARE_BD_CMD_MONITOR_CONTROL		= 16
VMWARE_BD_CMD_GET_HW_VERSION		= 17
VMWARE_BD_CMD_OS_NOT_FOUND		= 18
VMWARE_BD_CMD_GET_UUID			= 19
VMWARE_BD_CMD_GET_MEM_SIZE		= 20
VMWARE_BD_CMD_HOSTCOPY			= 21	# dev
VMWARE_BD_CMD_SERVICE_VM		= 22	# prototyping
VMWARE_BD_CMD_GETTIME			= 23	# deprecated
VMWARE_BD_CMD_STOP_CATCHUP		= 24
VMWARE_BD_CMD_PUTCHAR			= 25	# dev
VMWARE_BD_CMD_ENABLE_MSG		= 26	# dev
VMWARE_BD_CMD_GOTO_TCL			= 27	# dev
VMWARE_BD_CMD_INIT_PCIO_PROM		= 28
VMWARE_BD_CMD_INT13			= 29
VMWARE_BD_CMD_MESSAGE			= 30	# rpc
	# these go in high word of ecx
	VMWARE_BD_MSG_TYPE_OPEN		= 0
		VMWARE_CHAN_FLAG_COOKIE		= 0x80000000
		VMWARE_CHAN_MAX_CHANNELS	= 8
		VMWARE_CHAN_MAX_SIZE		= 65536
		VMWARE_CHAN_PROTO_TCLO		= 0x4f4c4354	# "TCLO"
		VMWARE_CHAN_PROTO_RPCI		= 0x49435052	# "RPCI"
	VMWARE_BD_MSG_TYPE_SENDSIZE	= 1
	VMWARE_BD_MSG_TYPE_SENDPAYLOAD	= 2
	VMWARE_BD_MSG_TYPE_RECVSIZE	= 3 #out:edx>>16=SENDSIZE;ebx=size
	VMWARE_BD_MSG_TYPE_RECVPAYLOAD	= 4
	VMWARE_BD_MSG_TYPE_RECVSTATUS	= 5
	VMWARE_BD_MSG_TYPE_CLOSE	= 6

	# returned in high word of ecx
	VMWARE_BD_MSG_ST_SUCCESS	= 1 << 0 #guest can set this bit only!
	VMWARE_BD_MSG_ST_DORECV		= 1 << 1
	VMWARE_BD_MSG_ST_CLOSED		= 1 << 2
	VMWARE_BD_MSG_ST_UNSENT		= 1 << 3 # removed before received
	VMWARE_BD_MSG_ST_CPT		= 1 << 4 # checkpoint
	VMWARE_BD_MSG_ST_POWEROFF	= 1 << 5
	VMWARE_BD_MSG_ST_TIMEOUT	= 1 << 6
	VMWARE_BD_MSG_ST_HB		= 1 << 7 # high bandwidth supported
VMWARE_BD_CMD_RESERVED1			= 31
VMWARE_BD_CMD_RESERVED2			= 32
VMWARE_BD_CMD_RESERVED3			= 33
VMWARE_BD_CMD_IS_ACPI_DISABLED		= 34
VMWARE_BD_CMD_TOE			= 35	# N/A
VMWARE_BD_CMD_IS_MOUSE_ABSOLUTE		= 36
VMWARE_BD_CMD_PATCH_SMBIOS_STRUCTS	= 37
VMWARE_BD_CMD_MAPMEP			= 38	# dev
VMWARE_BD_CMD_ABS_POINTER_DATA		= 39
VMWARE_BD_CMD_ABS_POINTER_STATUS	= 40
VMWARE_BD_CMD_ABS_POINTER_COMMAND	= 41
VMWARE_BD_CMD_TIMER_SPONGE		= 42
VMWARE_BD_CMD_PATCH_ACPI_TABLES		= 43
VMWARE_BD_CMD_DEVEL_FAKE_HARDWARE	= 44	# debug
VMWARE_BD_CMD_GET_HZ			= 45
VMWARE_BD_CMD_GET_TIME_FULL		= 46
VMWARE_BD_CMD_STATE_LOGGER		= 47
VMWARE_BD_CMD_CHECK_FORCE_BIOS_SETUP	= 48
VMWARE_BD_CMD_LAZY_TIMER_EMULATION	= 49
VMWARE_BD_CMD_BOS_BBS			= 50
VMWARE_BD_CMD_V_ASSERT			= 51
VMWARE_BD_CMD_IS_G_OS_DARWIN		= 52
VMWARE_BD_CMD_DEBUG_EVENT		= 53
VMWARE_BD_CMD_OS_NOT_MACOSX_SERVER 	= 54
VMWARE_BD_CMD_GET_TIME_FULL_WITH_LAG	= 55
VMWARE_BD_CMD_ACPI_HOTPLUG_DEVICE	= 56
VMWARE_BD_CMD_ACPI_HOTPLUG_MEMORY	= 57
VMWARE_BD_CMD_ACPI_HOTPLUG_CBRET	= 58
VMWARE_BD_CMD_GET_HOST_VIDEO_MODES	= 59
VMWARE_BD_CMD_ACPI_HOTPLUG_CPU		= 60
VMWARE_BD_CMD_USB_HOTPLUG_MOUSE		= 61
VMWARE_BD_CMD_XPMODE			= 62
VMWARE_BD_CMD_NESTING_CONTROL		= 63
VMWARE_BD_CMD_FIRMWARE_INIT		= 64




# VMWARE_BDOOR_CALL:
# in/out eax, dx: eax, ebx=size, ecx,      edx, esi,          edi
# VMWARE_BDOOR_HB_IN/OUT:
# rep insb/outsb: eax, ebx,      ecx=size, edx, esi=src addr, edi=dst addr, ebp

# retry macro's: when not succes and checkpoint, retry.

# don't use this directly!
.macro VMWARE_BDOOR_RETRY reg, retrylabel, oklabel=0
	test	\reg, VMWARE_BD_MSG_ST_SUCCESS << 16
	.ifc 0,\oklabel
	jnz	99f
	.else
	jnz	\oklabel
	.endif
	test	\reg, VMWARE_BD_MSG_ST_CPT << 16
	jnz	\retrylabel
99:	# out: nz = success; z=error
.endm


.macro VMWARE_BDOOR_CALL retry=0, preserve=0
	.if \preserve != 0
	push	\preserve
	.endif
	mov	eax, VMWARE_BD_MAGIC
	mov	dx, VMWARE_BD_PORT
	.if VMWARE_DEBUG > 1
		DEBUG_REGSTORE
		DEBUG "BDOOR CALL"
		DEBUG_DWORD ecx
	.endif
	in	eax, dx
	.if VMWARE_DEBUG > 1
		DEBUG_REGDIFF
	.endif
	.if \preserve != 0
	pop	\preserve
	.endif
	.ifc 0,\retry
	.else
	VMWARE_BDOOR_RETRY ecx, \retry
	.endif
.endm

.macro VMWARE_BD_MESSAGE
	VMWARE_BDOOR_CALL
.endm

#########################################################
# 'high bandwidth' (rep insb/outsb) calls:
VMWARE_BD_HB_PORT = 0x5659
VMWARE_BD_HB_CMD_MESSAGE = 0
VMWARE_BD_HB_CMD_VASSERT = 1

.macro VMWARE_BDOOR_HB_IN retry=0 preserve=0
	.if \preserve != 0
	push	\preserve
	.endif
	mov	eax, VMWARE_BD_MAGIC
	mov	dx, VMWARE_BD_HB_PORT
	rep	insb
	.if \preserve != 0
	pop	\preserve
	.endif
	.ifc 0,\retry
	.else
	VMWARE_BDOOR_RETRY ebx, \retry
	.endif
.endm

.macro VMWARE_BDOOR_HB_OUT retry=0 preserve=0
	.if \preserve != 0
	push	\preserve
	.endif
	mov	eax, VMWARE_BD_MAGIC
	mov	dx, VMWARE_BD_HB_PORT
	rep	outsb
	.if \preserve != 0
	pop	\preserve
	.endif
	.ifc 0,\retry
	.else
	VMWARE_BDOOR_RETRY ebx, \retry
	.endif
.endm

##############################################################################
.struct 0
vmware_chan_proto:	.long 0
vmware_chan_id:		.long 0	# easy xs: hi=channel (max 8); lo=VMWARE_BD_PORT
vmware_chan_cookie:	.long 0, 0
vmware_msg_buffer:	.long 0
vmware_msg_buffer_size:	.long 0	# allocated size
vmware_msg_len:		.long 0 # message size
vmware_buf_curptr$:	.long 0	# kludge to avoid using stack
vmware_msg_len_remain$: .long 0	# kludge to avoid using stack
VMWARE_CHAN_STRUCT_LEN = .
.data SECTION_DATA_BSS
vmware_detected:	.byte 0 # 0=not checked yet, 1=not vmware, 2=vmware
vmware_chan_rpcin:	.space VMWARE_CHAN_STRUCT_LEN
vmware_chan_rpcout:	.space VMWARE_CHAN_STRUCT_LEN

##############################################################################
.text32


vmware_detect:
	cmp	byte ptr [vmware_detected], 1
	jb	0f
	# cf=0: zf=0: no vmware; zf=1: vmware
	jnz	1f
	cmc
1:	ret
########
0:	inc	byte ptr [vmware_detected] # 1=checked

	pushad

	I "Virtual Machine: "
	mov	ebx, ~VMWARE_BD_MAGIC # must not be VMWARE_BD_MAGIC
	mov	ecx, (0xffff << 16) | VMWARE_BD_CMD_GET_VERSION # changes eax,ebx,ecx
	mov	esi, 0
	mov	edi, 0
	VMWARE_BDOOR_CALL
	cmp	eax, -1
	jz	9f
	cmp	ebx, VMWARE_BD_MAGIC
	jnz	9f
	printc 14, "VMWare "

	printcharc 8, 'v'
	mov	edx, eax
	call	printdec32
	printc	8, " VMX type "
	mov	edx, ecx
	call	printdec32 # only high word! (0x00000004)

	mov	ecx, VMWARE_BD_CMD_GET_HW_VERSION
	VMWARE_BDOOR_CALL
	printc	8, " HW version "
	mov	edx, eax
	call	printdec32

	mov	ecx, VMWARE_BD_CMD_GET_SCREEN_SIZE
	VMWARE_BDOOR_CALL
	cmp	eax, -1
	jz	1f	# no screen size available
	printc	8, " Screen Size:"
	mov	edx, eax
	shr	edx, 16
	call	printdec32
	mov	dx, ax
	printcharc 8, 'x'
	call	printdec32

1:	call	newline
	inc	byte ptr [vmware_detected] # 2=vmware detected
	popad
	clc
	ret
9:	printlnc 13, "Not running in vmware"
	popad
	stc
	ret

vmware_chan_open_rpcout:
	.if VMWARE_DEBUG > 1
		DEBUG "Open RPCOUT"
	.endif
	mov	eax, offset vmware_chan_rpcout
	mov	ebx, VMWARE_CHAN_PROTO_RPCI
	call	vmware_chan_open
	ret

vmware_chan_open_rpcin:
	.if VMWARE_DEBUG > 1
		DEBUG "Open RPCIN"
	.endif
	mov	eax, offset vmware_chan_rpcin
	mov	ebx, VMWARE_CHAN_PROTO_TCLO
	call	vmware_chan_open
	ret

# in: eax = channel ptr
# in: ebx = VMWARE_CHAN_PROTO_*
vmware_chan_open:
	cmp	[eax + vmware_chan_id], dword ptr 0
	jz	0f
	.if VMWARE_DEBUG > 1
		DEBUG "Channel still open"
	.endif
	clc
	ret
0:	I "Opening communication channel with vmware: "
	push	ebx
	mov	esi, esp
	mov	ecx, 4
	call	nprint
	pop	ebx
	mov	[eax + vmware_chan_proto], ebx

0:	mov	ecx, (VMWARE_BD_MSG_TYPE_OPEN << 16) | VMWARE_BD_CMD_MESSAGE
	or	ebx, VMWARE_CHAN_FLAG_COOKIE
	VMWARE_BDOOR_CALL retry=0b preserve=eax	# ebx is not modified
	jnz	1f	# success

0:	and	ebx, ~VMWARE_CHAN_FLAG_COOKIE	# try again without cookie
	mov	ecx, (VMWARE_BD_MSG_TYPE_OPEN << 16) | VMWARE_BD_CMD_MESSAGE
	VMWARE_BDOOR_CALL retry=0b preserve=eax
	jz	vmware_chan_open_error$

1:	mov	dx, VMWARE_BD_PORT
	mov	[eax + vmware_chan_id], edx
	mov	[eax + vmware_chan_cookie + 0], esi
	mov	[eax + vmware_chan_cookie + 4], edi
	OK
	clc
	ret

# in: eax = channel ptr
vmware_chan_close:
0:	mov	ecx, VMWARE_BD_CMD_MESSAGE | (VMWARE_BD_MSG_TYPE_CLOSE<<16)
	mov	edx, [eax + vmware_chan_id]
	mov	esi, [eax + vmware_chan_cookie + 0]
	mov	edi, [eax + vmware_chan_cookie + 4]
	VMWARE_BDOOR_CALL retry=0b preserve=eax
	jz	9f
	mov	[eax + vmware_chan_id], dword ptr 0
9:	ret


# in: eax = channel ptr
# out: esi, [eax + vmware_msg_buffer]
# out: ecx, [eax + vmware_msg_len]
# out: CF=1: no message.
vmware_chan_receive:
0:	mov	ecx, VMWARE_BD_CMD_MESSAGE | (VMWARE_BD_MSG_TYPE_RECVSIZE << 16)
	mov	edx, [eax + vmware_chan_id]
	mov	esi, [eax + vmware_chan_cookie + 0]
	mov	edi, [eax + vmware_chan_cookie + 4]
	VMWARE_BDOOR_CALL retry=0b preserve=eax
	jz	vmware_chan_error$
	test	ecx, VMWARE_BD_MSG_ST_DORECV << 16
	jnz	1f
	.if VMWARE_DEBUG
		call	vmware_chan_print_label$
		printc 11, ": "
		println "No message"
	.endif
	stc
	ret

1:	# get size
	shr	edx, 16
	cmp	dx, VMWARE_BD_MSG_TYPE_SENDSIZE
	jne	vmware_chan_prot_error1$
	mov	[eax + vmware_msg_len], ebx
	call	vmware_chan_alloc_buffer
	jc	vmware_mem_error$

	# a little kludge to avoid using the stack for easy jumping
	mov	edx, [eax + vmware_msg_buffer]
	mov	[eax + vmware_buf_curptr$], edx
	mov	edx, [eax + vmware_msg_len]
	mov	[eax + vmware_msg_len_remain$], edx

	test	ecx, VMWARE_BD_MSG_ST_HB << 16
.if !VMWARE_DISABLE_HB
	jnz	1f
.endif
######## slow method
0:	mov	ecx, (VMWARE_BD_MSG_TYPE_RECVPAYLOAD << 16)|VMWARE_BD_CMD_MESSAGE
	mov	edx, [eax + vmware_chan_id]
	mov	esi, [eax + vmware_chan_cookie + 0]
	mov	edi, [eax + vmware_chan_cookie + 4]
	mov	ebx, VMWARE_BD_MSG_ST_SUCCESS # prev req status
	VMWARE_BDOOR_CALL retry=vmware_chan_receive preserve=eax
	jz	vmware_chan_error$
	cmp	edx, VMWARE_BD_MSG_TYPE_SENDPAYLOAD << 16
	jne	vmware_chan_prot_error2$

	mov	edi, [eax + vmware_buf_curptr$]
	mov	[edi], ebx
	add	[eax + vmware_buf_curptr$], dword ptr 4

	sub	[eax + vmware_msg_len_remain$], dword ptr 4
	ja	0b # assume other bytes are 0 if last 1,2,3 bytes of msg
	mov	byte ptr [edi+4], 0 # asciz failsafe
	jmp	2f

######## fast method: rep insb
1:	mov	ecx, [eax + vmware_msg_len]
	mov	ebx, VMWARE_BD_HB_CMD_MESSAGE | (VMWARE_BD_MSG_ST_SUCCESS << 16)
	mov	edx, [eax + vmware_chan_id]
	mov	esi, [eax + vmware_chan_cookie + 0]
	mov	ebp, [eax + vmware_chan_cookie + 4]
	mov	edi, [eax + vmware_msg_buffer]
	VMWARE_BDOOR_HB_IN retry=vmware_chan_receive preserve=eax
	jz	vmware_chan_error$

2:	mov	ecx, [eax + vmware_msg_len]
	mov	esi, [eax + vmware_msg_buffer]

	.if VMWARE_DEBUG
		call	vmware_chan_print_label$
		printc	13, " RX "
		call	nprintln
	.endif

	push	esi
	push	ecx
	call	vmware_chan_receive_status$	# rpc call: finish receive message
	pop	ecx
	pop	esi
	ret

# in: eax = channel ptr
vmware_chan_receive_status$:
0:	mov	ecx, VMWARE_BD_CMD_MESSAGE | (VMWARE_BD_MSG_TYPE_RECVSTATUS << 16)
	mov	edx, [eax + vmware_chan_id]
	mov	esi, [eax + vmware_chan_cookie + 0]
	mov	edi, [eax + vmware_chan_cookie + 4]
	mov	ebx, VMWARE_BD_MSG_ST_SUCCESS # prev status
	VMWARE_BDOOR_CALL retry=0b preserve=eax
	jz	vmware_chan_error_status$
	ret


# in: eax = channel ptr
# in: ebx=msg size
# destroys: edx
vmware_chan_alloc_buffer:
	cmp	ebx, [eax + vmware_msg_buffer_size]
	ja	1f
	clc
	ret
1:	mov	edx, ebx
	mov	[eax + vmware_msg_buffer_size], edx
	push	eax
	mov	eax, [eax + vmware_msg_buffer]
	add	edx, 4	# for easy stosd (3) and trailing 0 (1)
	call	mrealloc	# old buffer will have been freed.
	pop	edx
	xchg	[edx + vmware_msg_buffer], eax
	jnc	1f
	call	mfree
	stc
1:	mov	eax, edx	# restore channel ptr
	ret

.if VMWARE_DEBUG
vmware_chan_print_label$:
	printc 11, "vmware "
	movzx	edx, word ptr [eax + vmware_chan_id + 2]
	call	printdec32
	printcharc 8, ':'
	push	esi
	push	ecx
	lea	esi, [eax + vmware_chan_proto]
	mov	ecx, 4
	call	nprint
	pop	ecx
	pop	esi
	ret
.endif

# in: eax = channel ptr
# in: esi, ecx = message
vmware_chan_send:
	.if VMWARE_DEBUG
		call	vmware_chan_print_label$
		printc 14, " TX "
		call	nprint
	.endif
	mov	[eax + vmware_buf_curptr$], esi
	mov	[eax + vmware_msg_len_remain$], ecx

0:	mov	ebx, [eax + vmware_msg_len_remain$]
	mov	ecx, VMWARE_BD_CMD_MESSAGE | (VMWARE_BD_MSG_TYPE_SENDSIZE << 16 )
	mov	edx, [eax + vmware_chan_id]
	mov	esi, [eax + vmware_chan_cookie + 0]
	mov	edi, [eax + vmware_chan_cookie + 4]
	VMWARE_BDOOR_CALL retry=0b preserve=eax
	test	ecx, VMWARE_BD_MSG_ST_HB << 16
.if !VMWARE_DISABLE_HB
	jnz	1f
.endif
######## slow method
2:	mov	ecx, [eax + vmware_buf_curptr$]
	mov	ebx, [ecx]
	mov	ecx, [vmware_msg_len_remain$]
	.if VMWARE_DEBUG > 1
		DEBUG_DWORD ecx # len
		DEBUG_DWORD ebx
		push	eax
		push	ebx
		.rept 4
		mov	al, bl
		call printchar
		shr	ebx, 8
		.endr
		pop	ebx
		pop	eax
	.endif
	cmp	ecx, 4
	mov	edx, 1
	jae	3f
	shl	cl, 3
	shl	edx, cl
	dec	edx
	and	ebx, edx
	.if VMWARE_DEBUG > 1
		DEBUG_DWORD edx
	.endif

#	and	ebx, 0x00ffffff
#	dec	eax
#	jz	3f
#	and	ebx, 0x0000ffff
#	dec	eax
#	js	3f
#	and	ebx, 0x000000ff
3:

	mov	ecx, VMWARE_BD_CMD_MESSAGE | (VMWARE_BD_MSG_TYPE_SENDPAYLOAD << 16)
	mov	edx, [eax + vmware_chan_id]
	mov	esi, [eax + vmware_chan_cookie + 0]
	mov	edi, [eax + vmware_chan_cookie + 4]

	VMWARE_BDOOR_CALL retry=0b preserve=eax
	jz	vmware_chan_error_send$
	add	[eax + vmware_buf_curptr$], dword ptr 4
	sub	[eax + vmware_msg_len_remain$], dword ptr 4
	ja	2b

	clc # just in case
	ret

######## fast method: rep outsb
1:	mov	ebx, VMWARE_BD_HB_CMD_MESSAGE | (VMWARE_BD_MSG_ST_SUCCESS << 16)
	mov	edx, [eax + vmware_chan_id]
	mov	ebp, [eax + vmware_chan_cookie + 0]
	mov	edi, [eax + vmware_chan_cookie + 4]
	mov	ecx, [eax + vmware_msg_len_remain$]
	mov	esi, [eax + vmware_buf_curptr$]
	VMWARE_BDOOR_HB_OUT retry=0b preserve=eax
	jz	vmware_chan_error_send$
	clc # just in case
	ret

#############################################


vmware_mem_error$:
	printlnc 4, "vmware communication error: can't allocate message buffer"
	stc
	ret

vmware_chan_open_error$:
	printlnc 4, "vmware communication error: cannot open channel"
	stc
	ret
vmware_chan_error$:
	printlnc 4, "vmware communication error"
	stc
	ret

vmware_chan_error_send$:
	printlnc 4, "vmware communication error: cannot send message"
	stc
	ret

vmware_chan_error_status$:
	printlnc 4, "vmware communication error: can't request status"
	stc
	ret

vmware_chan_prot_error1$:
	printlnc 4, "vmware protocol error: expect SENDSIZE from vmware"
	stc
	ret

vmware_chan_prot_error2$:
	printlnc 12, "vmware protocol error: expect SENDPAYLOAD from vmware"
	ret


##############################################################################
# in: esi = rpc message
vmware_rpc_call:
	call	strlen_
	#inc	ecx

	mov	eax, offset vmware_chan_rpcout
	call	vmware_chan_send
	jc	9f
	OK
	call	vmware_chan_receive
	jc	9f
	printc 11, "vmware RPC "
	cmp	word ptr [esi], 0x2031	# "1 "
	jz	2f
	printc 4, "ERROR: "
	cmp	word ptr [esi], 0x2030	# "0 "
	jz	3f
	printc	12, "malformed reply: "
	jmp	4f
3:	add	esi, 2
4:	call	println
	jmp	9f

2:	printc 	10, "OK"
	cmp	ecx, 2
	jbe	3f
	printc 10, ": "
3:	add	esi, 2
	call	println
9:	ret

##############################################################################
# Commandline Interface

cmd_vmcheck:
	call	vmware_detect
	jnc	0f
	printlnc 12, "no vmware"
	ret
########
0: 	
	push	esi
	call	vmware_chan_open_rpcin
	call	vmware_chan_open_rpcout
	pop	esi
	jc	9f

	lodsd
	lodsd
	or	eax,eax			# no arg: check for message
	jz	1f
	cmp	word ptr [eax], 'r'	# reset channel (close/open)
	jz	2f
	cmp	word ptr [eax], 'c'	# send caps
	jz	3f
	printlnc 12, "usage: vmcheck [r|c]"
	printlnc 12, "  no args: check for messages"
	printlnc 12, "  'r': reset channel; 'c': send capabilities"
	ret

######## check for message
1:	mov	eax, offset vmware_chan_rpcin
	call	vmware_chan_receive
	mov	eax, offset vmware_chan_rpcout
	call	vmware_chan_receive
	ret

######## reset channel
2:	mov	eax, offset vmware_chan_rpcin
	call	vmware_chan_close
	call	vmware_chan_open_rpcin
	mov	eax, offset vmware_chan_rpcout
	call	vmware_chan_close
	call	vmware_chan_open_rpcout
	ret

######## send message
3:	
	# first check if there is a message
	mov	eax, offset vmware_chan_rpcin
	call	vmware_chan_receive
	mov	eax, offset vmware_chan_rpcout
	call	vmware_chan_receive

	#LOAD_TXT "SetGuestInfo  1 unknown"
	#LOAD_TXT "tools.capability.features 4=1 5=1 6=1 7=1 25=1"
	#LOAD_TXT "machine.id.get\0\0\0\0"
	# major << 10 + minor << 5 + base
	# 8 4 2 -> 2052
	#LOAD_TXT "log foo: Hello!"

	LOAD_TXT "log QuRe VMWare handler initialized"
	call	vmware_rpc_call
	LOAD_TXT "tools.set.version 2147483647" # 0x7fffffff
	call	vmware_rpc_call
	LOAD_TXT "tools.capability.features 4=1 5=1 6=1 7=1 25=1"
	call	vmware_rpc_call
	LOAD_TXT "machine.id.get"
	call	vmware_rpc_call
	LOAD_TXT "tools.capability.hgfs_server toolbox 1"
	call	vmware_rpc_call

	ret

9:	printlnc 12, "open/close fail"
6:	ret

vmware_code_end:
	nop
