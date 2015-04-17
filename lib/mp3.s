#############################################################################
# MP3 Decoder
.intel_syntax noprefix

.data
mp3_bitrate_tbl_idx$:	# offsets into mp3_bitrate_tbl
# Version 1: layer I, II, III, invalid
.byte  0*2, 16*2, 32*2, 0
# Version 2
.byte 48*2, 64*2, 64*2, 0
# Version 2.5
.byte 48*2, 64*2, 64*2, 0
# Version 4 (invalid).
.byte  0*2,  0*2,  0*2, 0

mp3_bitrate_tbl$: # 5x 16 entries, in kbps.
# V1 = MPEG 1, V2 = MPEG 2 and MPEG 2.5
#
# MPEG 1:
# V1 L1		PATTERN: i*32
.word 0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, -1
# V1 L2		DELTA: 32,16,8,8,16,16,16,16,32,32,32,32,64,64
.word 0, 32, 48, 56,  64,  80,  96, 112, 128, 160, 192, 224, 256, 320, 384, -1
#mono:Y  Y   Y   Y    Y    Y    Y   Y    Y    Y    Y
#SID: Y               Y         Y   Y    Y    Y    Y    Y    Y    Y    Y
# S=stereo I=intensity stereo D=dual channel.

# V1 L3
.word 0, 32, 40, 48,  56,  64,  80,  96, 112, 128, 160, 192, 224, 256, 320, -1

# MPEG 2, MPEG 2.5:
# V2 L1
.word 0, 32, 48, 56,  64,  80,  96, 112, 128, 144, 160, 176, 192, 224, 256, -1
# V2 L2/L3
.word 0,  8, 16, 24,  32,  40,  48,  56,  64,  80,  96, 112, 128, 144, 160, -1

.text32
# in: al = [2 bit] version, ah = [2 bit] layer
# in: dl = [4 bit] bitrate index
mp3_lookup_bitrate:
	cmp	dl, 0b1111
	jz	9f
	shl	al, 4
	or	al, ah
	movzx	eax, al
	movzx	eax, byte ptr [mp3_bitrate_tbl_idx$ + eax]
	movzx	edx, dl
	movzx	eax, word ptr [mp3_bitrate_tbl$ + eax + edx * 2]
	ret
9:	mov	eax, -1
	ret
.text32



mp3_decode:
	enter	8, 0
	# ebp -1: layer
	# ebp -2 : version
	# ebp -4: samplerate
	push_	esi ecx
	DEBUG "mp3_decode"

	mov	edi, esi

	# find frame (len=4 bytes)
	# 11111111 111BBCCD EEEEFFGH IIJJKLMM
0:	or	ecx, ecx
	jle	91f #jecxz	91f
	# scan for 11 bits of 1
	mov	al, -1	# 11111111
	repnz	scasb
	jnz	91f
	mov	esi, edi
	lodsb		# 111BBCCD
		mov	dl, al; DEBUG "2nd byte";call printbin8
	mov	ah, al
	shr	ah, 5
	cmp	ah, 0b111
	jnz	0b

		mov	edx, edi
		sub	edx, [esp + 4]	# orig esi
		print "Frame offs "
		call	printhex8
		call	printspace
		mov	dl, al
		call	printbin8

	# BB: version
	#
	# official versions: 0b10 = MPEG2, 0b11=MPEG1 (so 12 bits of 1)
	# unofficial: 0b00=MPEG 2.5 (lo bitrate); 0b01=reserved

	# have:			want:
	# 00 = 2.5		00 = 1
	# 01 = reserved		01 = 2
	# 10 = 2		10 = 2.5
	# 11 = 1		11 = reserved
	
	# 00	-> 10	not->11	shr 1,xor -> 10
	# 01	-> 11	not->10 shr 1,xor -> 11
	# 10	-> 01	not->01 shr 1,xor -> 01
	# 11	-> 00	not->00 shr 1,xor -> 00

	mov	dl, al
	call printspace
	call printbin8
	call printspace
	shr	dl, 3
	not	dl
	and	dl, 3
	mov	dh, dl
	shr	dh, 1
	xor	dl, dh
	mov	[ebp - 2], dl
		inc	dl	# 1 .. 4
		print " Version "
		call	printhex1

	# CC: layer
	#
	# have:		want:		or want:
	# 00 = res	00 = I		00 = res
	# 01 = III	01 = II		01 = I
	# 10 = II	10 = III	10 = II
	# 11 = I	11 = res	11 = III

			#   not
			# 00->11
			# 01->10
			# 10->01
			# 11->00
	
	mov	dl, al
	shr	dl, 1
	not	dl
	and	dl, 3
	mov	[ebp - 1], dl
		inc	dl	# 1..4
		print " Layer "
		call	printhex1

		PRINTFLAG al, 1, "", " CRC16"
		call	newline
	
	lodsb	# EEEE FF G H
	mov	dl, al
		DEBUG "3rd byte";call printbin8
	shr	dl, 4
		DEBUG_BYTE dl, "bitrate index"
	mov	ax, [ebp - 2]	# al=version ah=layer
	call	mp3_lookup_bitrate
		mov	edx, eax
		call	printdec32
		print "kBps "

	mov	dl, al
	shr	dl, 2
	and	dl, 3
		DEBUG_BYTE dl, "samplerate"
		# 	MPEG1	MPEG2	MPEG2.5
		# 00	44100	22050	11025
		# 01	48000	24000	12000
		# 10	32000	16000	8000
		# 11 reserved
	.data
		mp3_samplerate_tbl$: .word 44100, 48000, 32000, 0
	.text32
	movzx	edx, dl
	movzx	edx, word ptr [mp3_samplerate_tbl$ + edx * 2]
	push	ecx
	mov	cl, [ebp - 2]	# get version, 0..3
	shr	edx, cl
	pop	ecx
		print "Samplerate: "
		call	printdec32
		call	printspace
	mov	[ebp - 4], edx
	
		PRINTFLAG al, 2, "padded"
		# layer I: 32 bit padding
		# layer II, III: 8 bit padding
	
		PRINTFLAG al, 1, "undefined"
	
	########### 4th byte
	lodsb	# II JJ K L MM
	mov	dl, al
		DEBUG "4th byte"; call printbin8
	shr	dl, 6
		# II: 00=stereo 01=joint stereo 10=dual channel, 11=mono
		DEBUG "Channel mode: "
		call	printhex1
	mov	dl, al
		shr	dl, 4
		and	dl, 3
		DEBUG "Mode Extension" # only if joint stereo
		# 32 sub-bands.
		#	I & II	   III
		#		M/S | Intensity
		# 00	 4-31	   0 0
		# 01	 8-31	   0 1
		# 10	12-31	   1 0
		# 11	16-31	   1 1
		call	printhex1

		PRINTFLAG al, 1<<3, "Copyright"
		PRINTFLAG al, 1<<2, "Original"
	mov	dl, al
	and	dl, 3
		# MM: Emphasis
		# 00 = none
		# 01 = 50/15 ms
		# 10 = reserved
		# 11 = CCIT J.17
		print "Emphasis: "
		call	printhex1
		call	newline
	

	############### END PHYSICAL FRAME HEADER #############

	# Next: side information. Mono: 17 bytes, stereo: 32 bytes.
	print "Side Information: "

	# layer3:
	# (from libmad)

	lodsd	; DEBUG_DWORD eax,"main_data_begin"
	lodsd	; DEBUG_DWORD eax,"private_bits"
	lodsb	; DEBUG_BYTE al,"scfsi[0]"
	lodsb	; DEBUG_BYTE al,"scfsi[1]"
	call	newline

	# granule[2] {
	#	channel[2] {
	lodsw	; DEBUG_WORD ax,"part_2_3_len"
	lodsw	; DEBUG_WORD ax,"big_values"
	lodsw	; DEBUG_WORD ax,"global_gain"
	lodsw	; DEBUG_WORD ax,"scalefac_compress"

	lodsb	; DEBUG_BYTE al, "flags"
	lodsb	; DEBUG_BYTE al, "block_type"
	lodsb	; DEBUG_BYTE al, "table_select"
	lodsb	; DEBUG_BYTE al, "table_select"
	lodsb	; DEBUG_BYTE al, "table_select"
	lodsb	; DEBUG_BYTE al, "subblock_gain"
	lodsb	; DEBUG_BYTE al, "subblock_gain"
	lodsb	; DEBUG_BYTE al, "subblock_gain"
	lodsb	; DEBUG_BYTE al, "region0_count"
	lodsb	; DEBUG_BYTE al, "region1_count"

	# main data: 39 bytes scalefac data
	#	}
	# }
	#

	print "Main Data: "
	push	ecx
	mov	ecx, 8
1:	lodsd
	mov	edx, eax
	call	printhex8
	call	printspace
	loop	1b
	pop	ecx
	call	newline




0:	pop_	ecx esi
	leave
	ret
91:	println "no more frames"
	jmp	0b
.include "../lib/mp3.s"
cmd_play_mp3:
	enter	8, 0
	LOAD_TXT "/c/test.mp3", eax
	mov	dl, [boot_drive]
	add	dl, 'a'
	mov	[eax+1], dl
	xor	edx, edx
	call	fs_open
	jc	9f
	mov	[ebp - 4], eax
	mov	eax, 2048*2
	call	mallocz
	jc	9f
	mov	[ebp - 8], eax

	mov	edi, eax
	mov	ecx, 2048*2
	mov	eax, [ebp - 4]
	call	fs_read
	jc	8f

	mov	esi, [ebp - 8]
	mov	ecx, 2048*2
	call	mp3_decode

	mov	eax, [ebp - 4]
8:	call	fs_close
	mov	eax, [ebp - 8]
	call	mfree
9:	leave
	ret
