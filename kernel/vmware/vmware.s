##############################################################################
## VMWare interface
#
# open-vm-tools/lib/include/backdoor_def.h, lib/rpcIn etc.
.intel_syntax noprefix

VMWARE_DEBUG = 1

VMWARE_DISABLE_HB = 1	# disable high bandwidth (rep insb/outsb)

##############################################################################
.data SECTION_DATA_BSS
vmware_detected:	.byte 0 # 0=not checked yet, 1=not vmware, 2=vmware
vmware_chan_rpcin:	.space VMWARE_CHAN_STRUCT_LEN
vmware_chan_rpcout:	.space VMWARE_CHAN_STRUCT_LEN

##############################################################################
.include "vmware/bdoor.s"
.include "vmware/vix.s"
.include "vmware/chan.s"
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

###############################################################################
# Channel setup

# Counter intuitive: the 'RPCI' protocol is RPC-OUT
vmware_chan_open_rpcout:
	.if VMWARE_DEBUG > 1
		DEBUG "Open RPCOUT"
	.endif
	mov	eax, offset vmware_chan_rpcout
	mov	ebx, VMWARE_CHAN_PROTO_RPCI
	call	vmware_chan_open
	ret

# The TCLO protocol is RPC-IN.
vmware_chan_open_rpcin:
	.if VMWARE_DEBUG > 1
		DEBUG "Open RPCIN"
	.endif
	mov	eax, offset vmware_chan_rpcin
	mov	ebx, VMWARE_CHAN_PROTO_TCLO
	call	vmware_chan_open
	ret

##############################################################################
# RPC-in 'TCLO' polling

vmware_tclo_poll:
	mov	eax, offset vmware_chan_rpcin
	LOAD_TXT ""
	xor	ecx, ecx
	call	vmware_chan_send
	jc	9f
	call	vmware_chan_receive
	jc	9f
	OK

	print "received: "
	DEBUG_DWORD ecx
	call nprint

	clc

9:	ret


# in: esi, ecx
vmware_tclo_handle:
	#############################
	# Handle the message


	# check for 'reset':
	cmp	ecx, 5
	jnz	1f
	cmp	[esi], dword ptr ('r')|('e'<<8)|('s'<<16)|('e'<<24)
	jnz	1f
	cmp	word ptr [esi+4], 't'
	jnz	1f
	LOAD_TXT "OK ATR toolbox"
	jmp	3f

1:	# check for 'ping'
#	cmp	ecx, 4 #msg size 5...?
#	jnz	1f
	cmp	[esi], dword ptr 'p'|('i'<<8)|('n'<<16)|('g'<<24)
	jnz	1f
	cmp	byte ptr [esi+4], 0
	jz	2f

1:	LOAD_TXT "DisplayTopology_Set ",edi
	push_	ecx esi
	mov	ecx, 20
	repz	cmpsb
	pop_	esi ecx
	jnz	1f
	# example: "DisplayTopology_Set 1 , 0 0 1920 1080"
	jmp	3f	# what's the response str sent here?

1:	cmp	[esi], dword ptr 'V'|('i'<<8)|('x'<<16)|('_'<<24)
	jnz	1f
	call	vmware_vix_handle_rpcin	# out: esi, ecx = resposne
	jc	4f	# malformed packet or unknown/unimplemented
	
        jmp     3f

####################

1:	# last check: nop.

# response
4:	LOAD_TXT "ERROR Unknown command"
	jmp	3f

2:	LOAD_TXT "OK "
3:	call	strlen_
	call	vmware_chan_send

9:	ret

##############################################################################

# in: esi = rpc message
vmware_rpc_call:
	mov	eax, offset vmware_chan_rpcout
	call	strlen_
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
	jz	vmw_poll$
	cmp	word ptr [eax], 'r'	# reset channel (close/open)
	jz	vmw_reset$
	cmp	word ptr [eax], 'c'	# send caps
	jz	vmw_caps$
	printlnc 12, "usage: vmcheck [r|c]"
	printlnc 12, "  no args: check for messages"
	printlnc 12, "  'r': reset channel; 'c': send capabilities"
	ret

9:	printlnc 12, "open/close fail"
	ret

##########################################
# Subcommands:

######## check for message
vmw_poll$:	
	# the 'TCLO' channel will not respond to vmware_chan_receive
	# unless a vmware_chan_send (empty message) is executed first.
	#mov	eax, offset vmware_chan_rpcin
	call	vmware_tclo_poll
	jc	1f
	call	vmware_tclo_handle
1:

	# This will probably not result in any messages, even though
	# it is possible.
	mov	eax, offset vmware_chan_rpcout
	call	vmware_chan_receive
	ret

######## reset channel
vmw_reset$:
	mov	eax, offset vmware_chan_rpcin
DEBUG "close chan rpcin"
	call	vmware_chan_close
DEBUG "open rpcin"
	call	vmware_chan_open_rpcin
	mov	eax, offset vmware_chan_rpcout
DEBUG "close rpcout"
	call	vmware_chan_close
DEBUG "open rpcout"
	call	vmware_chan_open_rpcout
	ret

######## send capabilities
vmw_caps$:	
	# first check if there is a message
	call	vmware_tclo_poll
	jc	1f
	call	vmware_tclo_handle
1:

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
/*
	LOAD_TXT "tools.set.version 2147483647" # 0x7fffffff
	call	vmware_rpc_call
	LOAD_TXT "tools.capability.features 4=1 5=1 6=1 7=1 25=1"
	call	vmware_rpc_call
	LOAD_TXT "machine.id.get"
	call	vmware_rpc_call
	LOAD_TXT "tools.capability.hgfs_server toolbox 1"
	call	vmware_rpc_call
*/
	LOAD_TXT "tools.capability.resolution_set 1"
	call	vmware_rpc_call
	LOAD_TXT "tools.capability.resolution_server toolbox 1"
	call	vmware_rpc_call
	LOAD_TXT "tools.capability.display_topology_set 1"
	call	vmware_rpc_call
	LOAD_TXT "tools.capability.color_depth_set 1"
	call	vmware_rpc_call
	LOAD_TXT "tools.capability.resolution_min 0 0"
	call	vmware_rpc_call
	LOAD_TXT "tools.capability.unity 1"
	call	vmware_rpc_call

	ret

# add message to host log
# in: esi, ecx
vmware_log$:
	.data
	vmw_msg_buf0$: .ascii "log "
	vmw_msg_buf$: .space 512
	.text32
	push_	esi ecx
	mov	edi, offset vmw_msg_buf$
	rep	movsb
	mov byte ptr [edi], 0
	pop_	ecx esi

	push_	eax esi ecx
	mov	eax, offset vmware_chan_rpcout
	mov	esi, offset vmw_msg_buf0$
	call	strlen_
	call	vmware_chan_send
	pop_	ecx esi eax
	ret


vmware_code_end:
	nop
