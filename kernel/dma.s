# ²²²²²²²²²²²²²²²²²²²²²²²²²²²²²²²²  DMA Library  ²²²²²²²²²²²²²²²²²²²²²²²²²²²²²²²
#
#       Written 1996, 2013
#
# 8237 DMA controller interface
#
# NOTE! This code only supports usage of 1 DMA channel at a time
########################################################################

.intel_syntax noprefix
.text32

.if DEFINE

DMA_DEBUG = 0

########################################################################
.data
dma_buffersize:	.long 0x4000        #INPUT!
dma_buffer_abs:	.long 0	# hw abs
dma_buffer:	.long 0

dma_mode:	.byte 0x58
dma_channel:	.byte 0

.endif

# Command bits for the command port
DMA_CMD_Mem2Mem         = 1   #enable mem to mem (chan 0+1)
DMA_CMD_Ch0_Hold        = 2
DMA_CMD_Disable         = 4   #disable controller
DMA_CMD_Compressed_Time = 8	# does not work: 25% speed incr
DMA_CMD_Rot_Priority    = 16  #Rotating priority (?)
DMA_CMD_Extended_Write  = 32  #1=Extended write mode# 0=late write
DMA_CMD_DRQ_Sense_Hi    = 64  #1=DRQ sensing = active high# 0=lo
DMA_CMD_DACK_Sense_Hi   = 128 #1=Dack sensing=active high# 0=lo

#* 1st & 2nd DMA Controler's ports *#

  DMA_Status:		.byte 0x08, 0xD0    #R Status reg
					#   0-3:chan. reached terminal count.
					#   4-7:chan. request pending.
  DMA_Command:		.byte 0x08, 0xD0    #W Command (see above)
  DMA_Request:		.byte 0x09, 0xD2    #W Request reg
					#   0-1:channel
					#   2  :set request bit for channel
  DMA_Single_Mask:	.byte 0x0A, 0xD4    #W Single Mask reg
					#   0-1:channel
					#   2  :1=set mask, 0=clear mask
  DMA_ModeReg:		.byte 0x0B, 0xD6    #W Mode register
					#   0-1:channel
  	DMA_MODE_WRITE	= 0b01<<2
  	DMA_MODE_READ	= 0b10<<2
					#   2-3:transfer type
					#        00=verify=nop/self test
					#        01=write
	DMA_MODE_AUTO	= 1<<4
					#        10=read
					#   4  :enable auto init[reset on complete]
	DMA_MODE_INCR	= 0<<5
	DMA_MODE_DECR	= 1<<5
					#   5  :0=address increment, 1=dec
	DMA_MODE_DEMAND	= 0b00<<6
	DMA_MODE_SINGLE	= 0b01<<6
	DMA_MODE_BLOCK	= 0b10<<6
	DMA_MODE_CASCADE= 0b11<<6

        #The DMA Mode constants
.if 0
        DMAM_Verify             = 0b00000000
        DMAM_Write              = 0b00000100
        DMAM_Read               = 0b00001000
        DMAM_AutoInit           = 0b00010000
        DMAM_Inc                = 0b00100000
        DMAM_Dec                = 0b00000000

        DMAM_Demand             = 0b00000000
        DMAM_Single             = 0b01000000
        DMAM_Block              = 0b10000000
        DMAM_Cascade            = 0b11000000
.endif
					#   6-7: 00=demand mode
					#        01=single
					#        10=block
					#        11=cascade

.if DEFINE
  DMA_ClearFlipFlop:	.byte 0x0C, 0xD8    #W Clear byte ptr flip-flop  (Write
					# means clear ff: first OUT16=low byte)
  DMA_MasterReset:	.byte 0x0D, 0xDA    #W Master Clear (reset)
					#R Last byte in MEM2MEM (unused)
  DMA_ClearMask:	.byte 0x0E, 0xDC    #W Clear mask register (Clear all masks)
  DMA_WriteAll:		.byte 0x0F, 0xDE    #W Master Clear (all Mask) [multichannel mask]
					#   0-3: mask channel (0=chan0, 1=chan1)

# * ports for 8 channels *#

DMA_Page        : .byte 0x87, 0x83, 0x81, 0x82, 0x8F, 0x8B, 0x89, 0x8A # page register
DMA_Address     : .byte 0x00, 0x02, 0x04, 0x06, 0xC0, 0xC4, 0xC8, 0xCC # base adddress
DMA_Count       : .byte 0x01, 0x03, 0x05, 0x07, 0xC2, 0xC6, 0xCA, 0xCE # base count

##############################################################################
.text32

# in: ah=channel
dma_stop:
	push_	ax bx
	movzx	ebx, ah
	shr	bl, 2
	movzx	dx, byte ptr [DMA_Single_Mask+ebx]
	mov	al, ah
	and	al, 3
	or	al, 4
	out	dx, al
	pop_	bx ax
	ret


# in: [dma_buffersize]
# out: ecx = [dma_buffersize]
# out: eax = [dma_buffer]
dma_allocbuffer:
	push_	edx edi

	mov	eax, [dma_buffer]
	or	eax, eax
	jz	1f
	call	mfree
1:

	mov	eax, [dma_buffersize]
	inc	eax
	and	eax, ~0x3
	mov	[dma_buffersize], eax
	mov	ecx, eax
		
	mov	edx, 0x10000
	call	malloc_aligned
	jc	91f

	mov	[dma_buffer], eax
	mov	edi, eax
	GDT_GET_BASE edx, ds
	add	eax, edx
	mov	[dma_buffer_abs], eax

	shr	ecx, 2
	mov	eax, 0x80808080
	rep	stosd	# qemu reboots 2nd time

	mov	ecx, [dma_buffersize]
0:	pop_	edi edx
	ret
91:	printlnc 4, "DMA_MakeBuffer: malloc fail"
	stc
	jmp	0b


dma_freebuffer:
	xor	eax, eax
	xchg	eax, [dma_buffer]
	call	mfree
	ret



# in: ah=dma channel
# out: dx=position
# out: CF
dma_getpos:
	push_	ebx ecx eax
	movzx	ebx, ah
	shr	bx, 2
	xor	dh, dh
	mov	dl, [DMA_ClearFlipFlop+ebx]
	out	dx, al          #AL can be anything
	mov	bl, ah
	mov	dl, [DMA_Count+ebx]
	cli
	mov	ecx, 100
	xor	eax, eax
0:	dec	ecx
	js	9f
	in	al, dx
	mov	ah, al
	in	al, dx	      # bx = first word count sample
	xchg	al, ah
	mov	bx, ax
	in	al, dx
	mov	ah, al	      # ax = second word count sample
	in	al, dx
	xchg	al, ah
	sub	bx, ax	      # compare the two
	cmp	bx, 4	      # difference over 4 then read again
	jg	0b
	cmp	bx, -4
	jl	0b
	cmp	eax, [dma_buffersize]    # check for bogus value
	jae	0b

	mov	cl, [esp+1] # get ah from stack
	shr	cl, 2
	shl	eax, cl		# if chan >=4 convert wordcount to bytecount
	mov	edx, [dma_buffersize]    # justify value : pos=size-word count
	sub	edx, eax
	clc
0:	sti
	pop_	eax ecx ebx
	ret
9:	mov	edx, -1
	stc
	jmp	0b


# in: al = mode (bits 0..1 ignored)
# in: ah = channel (0..7)
# in: ebx = dma buffer physical address
# in: ecx =  bytes to transfer (max 64kb for chan <=4, max 128kb for chan>4)
dma_transfer:	# Proc Far
	push_   eax cx ebx dx di
	and	ah, 7
	mov	[dma_channel], ah
	and	al, NOT 3                #erase the channel bits
	mov	[dma_mode], al

	mov	ebx, [dma_buffer_abs]#[dma_buffer]

	# -----  set channel mask register ------
	movzx	edi, byte ptr [dma_channel]
	mov	ax, di
	shr	di, 2                    #bit indicates controller 1/2
	and	al, 0b0011		# channel
	or	al, 0b0100               # mask
	movzx	dx, byte ptr [DMA_Single_Mask+edi]
	out	dx, al
	# ----- set mode register ------
	and	al, 3
	or	al, [dma_mode]
	mov	dl, [DMA_ModeReg+edi]
	out	dx, al

	# ------  clear MSB/LSB flip flop -----------
	mov	dl, [DMA_ClearFlipFlop+edi]
	out	dx, al

	#---- set byte count register ----
	movzx	di, byte ptr [dma_channel]
	mov	eax, ecx
	mov	cx, di
	shr	cx, 2                    #if dma >3 then shr 1 else shr 0
	shr	eax, cl                  # divide count address by 2 for DMA # 2
	dec	ax                      # count - 1
	mov	dl, [DMA_Count+edi]
	out	dx, al                   # bits 0..7
	xchg	al, ah
	out	dx, al                   # bits 8..15

	# ------  clear MSB/LSB flip flop -----------
	mov	dl, [DMA_ClearFlipFlop+edi] # again!
	out	dx, al

	#---- set channel base address ---
	# not ebx: only low 16 bits are /2 for dma controller 2
	shr	bx, cl                  # divide base address by 2 for DMA # 2
	mov	al, bl                   # set bits 0..7
	mov	dl, [DMA_Address+edi]
	out	dx, al
	mov	al, bh                   # set bits 8..15
	out	dx, al

#		shr	ebx, 15           # divide base address by 8000h for DMA # 2
#		xor	cl, 1
#		shr	ebx, cl           # divide base address by 10000h for DMA # 1
	shr	ebx, 16	# shift 23:16 into range
	mov	al, bl            # set bits 16..23 ( in LSB page register )
	mov	dl, [DMA_Page+edi]
	out	dx, al

	# -----  clear channel (mask register) ------
	mov	ax, di
	shr	di, 2
	and	al, 0x03	# channel; mask 0 = unmask
	mov	dl, [DMA_Single_Mask+edi]
	out	dx, al
	.if DMA_DEBUG > 1
		movzx	edi, byte ptr [dma_channel]
		shr	edi, 2
		DEBUG "DMA Controller"
		xor	dh, dh

		mov	dl, [edi + DMA_Status]
		in	al, dx
		DEBUG_BYTE al, "Status"

		mov	dl, [edi + DMA_MasterReset]
		in	al, dx
		DEBUG_BYTE al, "Intermed"

		mov	dl, [edi + DMA_Single_Mask]
		in	al, dx
		DEBUG_BYTE al, "Single Mask"

		mov	dl, [edi + DMA_Request]
		in	al, dx
		DEBUG_BYTE al, "Request"

		call	newline
	.endif

	pop_	di dx ebx cx eax
	ret
.endif
