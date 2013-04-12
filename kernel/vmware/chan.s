.intel_syntax noprefix

# Channel object declaration
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

.text32

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
	jz	vmware_chan_close_error$
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
DEBUG "fast"
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
		printc	13, " RX '"
		call	nprint
		printcharc 13, '\''
	.endif

	push	esi
	push	ecx
	call	vmware_chan_receive_status$	# rpc call: finish receive message
	pop	ecx
	pop	esi
	pushf
	call	newline
	popf
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
# in: esi, ecx = message
vmware_chan_send:
	.if VMWARE_DEBUG
		#push edx
		#mov edx, [esp + 4]
		#call	debug_printsymbol
		#pop edx
		DEBUG_DWORD eax
		call	vmware_chan_print_label$
		printc 14, " TX '"
		call	nprint
		printcharc 14, '\''
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
2:	mov	ecx, [eax + vmware_msg_len_remain$]
	#jecxz	9f	# no payload
	or ecx,ecx;jz 9f
	mov	ebx, [eax + vmware_buf_curptr$]
	mov	ebx, [ebx]
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
	# use edx to mask ebx
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
3:	mov	ecx, VMWARE_BD_CMD_MESSAGE | (VMWARE_BD_MSG_TYPE_SENDPAYLOAD << 16)
	mov	edx, [eax + vmware_chan_id]
	mov	esi, [eax + vmware_chan_cookie + 0]
	mov	edi, [eax + vmware_chan_cookie + 4]
	VMWARE_BDOOR_CALL retry=0b preserve=eax
	jz	vmware_chan_error_send$
	add	[eax + vmware_buf_curptr$], dword ptr 4
	sub	[eax + vmware_msg_len_remain$], dword ptr 4
	ja	2b

9:	call	newline
#push_ esi ecx
#call	vmware_chan_receive_status$
#pop_ ecx esi
	clc # just in case
	ret

######## fast method: rep outsb
1:	mov	ebx, VMWARE_BD_HB_CMD_MESSAGE | (VMWARE_BD_MSG_ST_SUCCESS << 16)
	mov	edx, [eax + vmware_chan_id]
	mov	ebp, [eax + vmware_chan_cookie + 0]
	mov	edi, [eax + vmware_chan_cookie + 4]
	mov	ecx, [eax + vmware_msg_len_remain$]
	jecxz	9b # 9f is too far
	mov	esi, [eax + vmware_buf_curptr$]
	VMWARE_BDOOR_HB_OUT retry=0b preserve=eax
	jz	vmware_chan_error_send$
9:	call	newline
#push_ esi ecx
#call	vmware_chan_receive_status$
#pop_ ecx esi
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

vmware_chan_close_error$:
	printlnc 4, "vmware communication error: cannot close channel"
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


############################################################################
# Utility


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


