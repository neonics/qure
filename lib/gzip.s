# RFC 1952 GZIP file format
# RFC 1951 DEFLATE compressed data format
# RFC 1950 ZLIB file format

# DEFLATE: Huffman + Lempel-Ziv 77.


# DEFLATE: stream of blocks.
#
# block: 3 bit header:
# bit 0: 1=last block in stream; 0: more blocks follow
# bits 1,2:
#  00=uncompressed, max 64kb
#  01=compressed with pre-agreed static huffman tree
#  10=compressed with provided huffman table
#  11=reserved.
#
# The Algorithm
#
# find longest duplicate substring of current string
# and output a distance, length pair.
#
# Decompression
#
# Length can exceed distance if a substring is repeated
# more than once.
# In assembly, this is equivalent to:
#
#	mov	ebx, esi
#	xor	eax, eax
#	lodsb		# load length code
#	mov	ecx, eax
#	jecxz	finished
#    	lodsb		# load offset code
#	neg	eax
#	lea	esi, [edi + eax]
#	rep movsb
#	mov	esi, ebx
#
# where esi + ecx > edi.
#
# esi refers to the input data, an array of length,offset pairs.
# edi refers to the output.
#
# Required output modes:
# 1) literal, as there has to be data to refer to.
# 2) substring repetition as described above
# 3) an escape sequence.
#
# Compression
#
# init:
#	pushd	ecx		# remaining input length
#	pushd	0		# best substring offset
#	pushd	0		# max substring identity (identicalness)
#	mov	ebx, edi	# output start
#	mov	ebp, esi	# input start
#
#	jmp	process
#
# done: add	esp, 12
#	ret
#
# process:
#	mov	ecx, esi
#	sub	ecx, ebp
#	jz	done
#	
#	lodsb
#	mov	ecx, edi
#	sub	ecx, ebx	# max scan len
#	# limited buffer aspect: window constraint
#	# cmp	ecx, WINDOW_SIZE; jbe 1f; mov ecx WINDOW_SIZE; 1:
# scan:
#	std
#	repnz	scasb
#	cld
#	jz	prefixmatch
#	mov	ah, al
#	mov	al, NEW_CHARACTER
#	cmpd	[esp], 0
#	jnz	nomorematches
#	jmp	out
#
# nomorematches:		# implies there is a match
#	mov	al, PAIR	# code
#	stosb
#	mov	eax, [esp]	# len
#	stosw			# max window len 64kb; else stosd
#	mov	eax, [esp + 4]
#	stos
#	mov	al, PAIR	# argument to compact
# out:	stosw
#	call	compact
#	jmp	process
#
# prefixmatch:
#	#inc	edi?
#	mov	edx, ecx
#	repz	cmpsb
#	sub	edx, ecx	# -matchlen
#	lea	esi, [esi+edx]	# reset esi to scan state
#	cmp	edx, [esp]	# match longer?
#	jnb	scan		# already have a longer match (note! negative!)
#	mov	[esp], edx	# record maxlen 
#	mov	[esp+4],edi	# record end offset
#	jmp	scan
#
# note that not using 'jz' also means that always the most recent
# match will be used, thus reducing window size.
#
# The output buffer will require to be at minimum twice the size
# of the input buffer for only unique characters,
# and maximally about 5 times.
#
# Re-coding the output in a temporary format:
# Due to the compact being called after each output sequence,
# the output buffer may well be a stackpointer used as an argument
# to an append_token buffer.
#
# compact:
#	mov	eax, edi	# output end
#	sub	eax, ebx	# newly appended output
#
# The compression as yet cannot use the most optimum prefix encoding
# because the data is not yet complete.
#
# However, what can be done is to limit buffer usage.
# Given a window size of 32kb, the maximum standard supported in GZip,
# a fixed buffer size of possibly a factor 1 times the window size
# can be used.
#
# The first decision is to not record repetitions of single characters,
# as that requires one code for the character literal, and one code
# for a single repetition, which is redundant.
#
#	cmp	al, PAIR
#	jnz	literal
#	cmp	[esp], 1
#	ja	recordsubstring
#
# literal:
#
#
# Therefore, the minimum repetition size will be 2. This means in
# a window of N bytes, there will be at most N/2 repetition codes
# to be stored. Since the window is 15 bits wide, this requires
# (for a window of 32kb) 16k * 2b = 32kb to record repetition
# lengths. The repetition offsets can be encoded by their position
# in the length buffers, using the extra bit to indicate the oddity
# of the offset.
#
#
# recordsubstring:
#	mov	edx, [esp]	# -repetition length
#	mov	eax, [esp + 4]	# repetition end
#	add	eax, edx	# repetition start
#	sub	eax, ebx	# relative to sliding window
#	mov	ebx, [window]
#	mov	[ebx + eax * 2], dx	# record length of substring 
#
# Now, this will store 
#
#
#
#	
#	ret
#



#####
# LIBRARY 
#	


.struct 0	# GZIP header: 10 bytes
gzip_magic: .word 0; GZIP_MAGIC = 0x8b1f
gzip_cm:	.byte 0		# compression method
	# 0..7 reserved
	GZIP_CM_DEFLATE = 8	
gzip_flags:	.byte 0
	GZIP_FLAG_FTEXT		= 1<<0	# ascii
	GZIP_FLAG_FHCRC		= 1<<1	# crc16 of header (crc32 & 0xffff)
	GZIP_FLAG_EXTRA		= 1<<2
	GZIP_FLAG_NAME		= 1<<3	# zero terminated
	GZIP_FLAG_FCOMMENT	= 1<<4	# zero terminated
	# other bits reserved
gzip_mtime:	.long 0	# original file mtime in Unix fmt (seconds since epoch GMT 1970)
gzip_xfl:	.byte 0	# extra flags
	GZIP_XFL_SIZE	= 2	# maximum compression
	GZIP_XFL_SPEED	= 4	# fastest algorithm
gzip_os:	.byte 0		# operating system (really source filesystem)
#0 - FAT filesystem (MS-DOS, OS/2, NT/Win32)
#1 - Amiga
#2 - VMS (or OpenVMS)
#3 - Unix
#4 - VM/CMS
#5 - Atari TOS
#6 - HPFS filesystem (OS/2, NT)
#7 - Macintosh
#8 - Z-System
#9 - CP/M
#10 - TOPS-20
#11 - NTFS filesystem (NT)
#12 - QDOS
#13 - Acorn RISCOS
#255 - unknown

gzip_opt_headers:
# optional header sequence:
# - EXTRA
# - NAME
# - COMMENT
# - FHCRC

.struct 0	# GZIP_FLAG_EXTRA
gzip_xlen:	.word 0
gzip_xdata:	# xlen bytes of data: a number of gzip_xdata structs.

.struct 0	# gzip_xdata struct
gzip_xdata_magic:	.word 0	# usually 2 ascii
gzip_xdata_len:		.word 0	# bytes to follow



# then: DEFLATE payload

.struct 0	# gzip_footer
gzip_crc32:	.long 0
gzip_orig_size:	.long 0

.data
# TEMPORARY!!! static data
_gzip_crc32$:	.long 0
_gzip_origsize$:.long 0


.text32
gzip:
	call	gzip_header
	call	gzip_deflate
	call	gzip_footer
	ret

gzip_deflate:
	mov	eax, 3	# gzip empty does 3
	stosw	# gzip empty does stosw
	ret

# in: esi = data
# in: ecx = datalen
# in: edi = buffer
# in: edx = buffer size
gzip_header:
	mov	eax, GZIP_MAGIC | 8<<16 | 0 << 24
	stosd	# magic, method, flags
	xor	eax, eax
	stosd	# mtime
	mov	ax, 0x300	# 03: unix; 00: no extra flags
	stosw
	ret

gzip_footer:
	push	esi
	mov	esi, offset _gzip_crc32$
	movsd
	movsd
	pop	esi
	ret
