# AES-128-ECB

# Rijndael. Based on https://github.com/kokke/tiny-AES128-C

############### INC
#include <stdint.h>

#void AES128_ECB_encrypt(uint8_t* input, const uint8_t* key, uint8_t *output);
# in: esi: input
# in: eax: key
# in: edi: output
#void AES128_ECB_decrypt(uint8_t* input, const uint8_t* key, uint8_t *output);
# in: esi: input
# in: eax: key
# in: edi: output


/*****************************************************************************/
/* Defines:                                                                  */
/*****************************************************************************/
# The number of columns comprising a state in AES. This is a constant in AES. Value=4
Nb = 4		#define Nb 4
# The number of 32 bit words in a key.
Nk = 4		#define Nk 4
# Key length in bytes [128 bit]
keyln = 16	#define keyln 16
# The number of rounds in AES Cipher.  (192, 156 have 12 or more rounds)
Nr = 10		#define Nr 10

#// jcallan@github points out that declaring Multiply as a function 
#// reduces code size considerably with the Keil ARM compiler.
#// See this link for more information: https://github.com/kokke/tiny-AES128-C/pull/3
#ifndef MULTIPLY_AS_A_FUNCTION
  #define MULTIPLY_AS_A_FUNCTION 0
#endif

/*****************************************************************************/
/* Private variables:                                                        */
/*****************************************************************************/
.data SECTION_DATA_BSS
# state - array holding the intermediate results during decryption.
#typedef uint8_t state_t[4][4];
#static state_t* state;
aes_128_state: .space 16

# The array that stores the round keys.
# static uint8_t RoundKey[176];
aes_128_RoundKey: .space 176

# The Key input to the AES Program
#static const uint8_t* Key;
aes_128_Key: .long 0	# ptr to bytes

.data
# The lookup-tables are marked const so they can be placed in read-only storage instead of RAM
# The numbers below can be computed dynamically trading ROM for RAM - 
# This can be useful in (embedded) bootloader applications, where ROM is often limited.
#static const uint8_t sbox[256] =   {
aes_128_sbox: 
  #0     1    2      3     4    5     6     7      8    9     A      B    C     D     E     F
.byte  0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76
.byte  0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0
.byte  0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15
.byte  0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75
.byte  0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84
.byte  0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf
.byte  0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8
.byte  0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2
.byte  0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73
.byte  0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb
.byte  0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79
.byte  0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08
.byte  0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a
.byte  0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e
.byte  0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf
.byte  0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
#};

#static const uint8_t rsbox[256] = {
aes_128_rsbox:
.byte  0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb
.byte  0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb
.byte  0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e
.byte  0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25
.byte  0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92
.byte  0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84
.byte  0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06
.byte  0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b
.byte  0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73
.byte  0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e
.byte  0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b
.byte  0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4
.byte  0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f
.byte  0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef
.byte  0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61
.byte  0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d
#};

# The round constant word array, Rcon[i], contains the values given by 
# x to th e power (i-1) being powers of x (x is denoted as {02}) in the field GF(2^8)
# Note that i starts at 1, not 0).
#static const uint8_t Rcon[255] = {
aes_128_Rcon:
.byte  0x8d, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36, 0x6c, 0xd8, 0xab, 0x4d, 0x9a
.byte  0x2f, 0x5e, 0xbc, 0x63, 0xc6, 0x97, 0x35, 0x6a, 0xd4, 0xb3, 0x7d, 0xfa, 0xef, 0xc5, 0x91, 0x39
.byte  0x72, 0xe4, 0xd3, 0xbd, 0x61, 0xc2, 0x9f, 0x25, 0x4a, 0x94, 0x33, 0x66, 0xcc, 0x83, 0x1d, 0x3a
.byte  0x74, 0xe8, 0xcb, 0x8d, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36, 0x6c, 0xd8
.byte  0xab, 0x4d, 0x9a, 0x2f, 0x5e, 0xbc, 0x63, 0xc6, 0x97, 0x35, 0x6a, 0xd4, 0xb3, 0x7d, 0xfa, 0xef
.byte  0xc5, 0x91, 0x39, 0x72, 0xe4, 0xd3, 0xbd, 0x61, 0xc2, 0x9f, 0x25, 0x4a, 0x94, 0x33, 0x66, 0xcc
.byte  0x83, 0x1d, 0x3a, 0x74, 0xe8, 0xcb, 0x8d, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b
.byte  0x36, 0x6c, 0xd8, 0xab, 0x4d, 0x9a, 0x2f, 0x5e, 0xbc, 0x63, 0xc6, 0x97, 0x35, 0x6a, 0xd4, 0xb3
.byte  0x7d, 0xfa, 0xef, 0xc5, 0x91, 0x39, 0x72, 0xe4, 0xd3, 0xbd, 0x61, 0xc2, 0x9f, 0x25, 0x4a, 0x94
.byte  0x33, 0x66, 0xcc, 0x83, 0x1d, 0x3a, 0x74, 0xe8, 0xcb, 0x8d, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
.byte  0x40, 0x80, 0x1b, 0x36, 0x6c, 0xd8, 0xab, 0x4d, 0x9a, 0x2f, 0x5e, 0xbc, 0x63, 0xc6, 0x97, 0x35
.byte  0x6a, 0xd4, 0xb3, 0x7d, 0xfa, 0xef, 0xc5, 0x91, 0x39, 0x72, 0xe4, 0xd3, 0xbd, 0x61, 0xc2, 0x9f
.byte  0x25, 0x4a, 0x94, 0x33, 0x66, 0xcc, 0x83, 0x1d, 0x3a, 0x74, 0xe8, 0xcb, 0x8d, 0x01, 0x02, 0x04
.byte  0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36, 0x6c, 0xd8, 0xab, 0x4d, 0x9a, 0x2f, 0x5e, 0xbc, 0x63
.byte  0xc6, 0x97, 0x35, 0x6a, 0xd4, 0xb3, 0x7d, 0xfa, 0xef, 0xc5, 0x91, 0x39, 0x72, 0xe4, 0xd3, 0xbd
.byte  0x61, 0xc2, 0x9f, 0x25, 0x4a, 0x94, 0x33, 0x66, 0xcc, 0x83, 0x1d, 0x3a, 0x74, 0xe8, 0xcb 
#};


.text32
/*****************************************************************************/
/* Private functions:                                                        */
/*****************************************************************************/
#static uint8_t getSBoxValue(uint8_t num)
#{
#  return sbox[num];
#}

# prints 16 hex bytes
# in: esi
ph:	
	push_	edx esi ecx
	mov	ecx, 16
0:	mov	dl, [esi]
	call	printhex2
	inc	esi
	call	printspace
	loop	0b
	call	newline
	pop_	ecx esi edx
	ret

# in: al
# out: al
aes_128_getSBoxValue:
	movzx	eax, al
	mov	al, [aes_128_sbox + eax]
	ret

#static uint8_t getSBoxInvert(uint8_t num)
#{
#  return rsbox[num];
#}
aes_128_getSBoxInvert:
	movzx	eax, al
	mov	al, [aes_128_rsbox + eax]
	ret

#// This function produces Nb(Nr+1) round keys. The round keys are used in each round to decrypt the states. 
#static void KeyExpansion(void)
#{
aes_128_KeyExpansion:
	push_	eax ebx ecx edx esi edi
#  uint32_t i, j, k;
#  uint8_t tempa[4]; // Used for the column/row operations
  
#  // The first round key is the key itself.
#  for(i = 0; i < Nk; ++i)
#  {
#    RoundKey[(i * 4) + 0] = Key[(i * 4) + 0];
#    RoundKey[(i * 4) + 1] = Key[(i * 4) + 1];
#    RoundKey[(i * 4) + 2] = Key[(i * 4) + 2];
#    RoundKey[(i * 4) + 3] = Key[(i * 4) + 3];
#  }

	mov	ecx, Nk
	mov	esi, [aes_128_Key]	# TODO: init!
	mov	edi, offset aes_128_RoundKey
	rep	movsd

# verified		println "KeyExpansion: "; push esi; mov esi, offset aes_128_RoundKey; call ph; pop esi

#  // All other round keys are found from the previous round keys.
	mov	ebx, Nk		# i
#  for(; (i < (Nb * (Nr + 1))); ++i)
#  {
0:	cmp	ebx, Nb * ( Nr + 1 )
	jnb	0f

	#	print "== Round "; push	ebx; call	_s_printdec32; print " = ";



#    for(j = 0; j < 4; ++j)  tempa[j]=RoundKey[(i-1) * 4 + j];
	mov	edx, [aes_128_RoundKey + ebx * 4 - 4]	# edx=tempa

	#	print "tempa: "; call	printhex8; call	newline;

#    if (i % Nk == 0)
#    {
	# Nk = 4, so we can test:
	test	bl, 3
	jnz	1f

      # This function rotates the 4 bytes in a word to the left once.
      # [a0,a1,a2,a3] becomes [a1,a2,a3,a0]

      # Function RotWord()
      #{
      #  k = tempa[0];
      #  tempa[0] = tempa[1];
      #  tempa[1] = tempa[2];
      #  tempa[2] = tempa[3];
      #  tempa[3] = k;
      #}
      	ror	edx, 8

      # SubWord() is a function that takes a four-byte input word and 
      # applies the S-box to each of the four bytes to produce an output word.

      # Function Subword()
      #{
      #  tempa[0] = getSBoxValue(tempa[0]);
      #  tempa[1] = getSBoxValue(tempa[1]);
      #  tempa[2] = getSBoxValue(tempa[2]);
      #  tempa[3] = getSBoxValue(tempa[3]);
      #}
	xor	eax, eax	# save on movzx eax, dl
	.rept 4
	mov	al, dl
	mov	dl, [aes_128_sbox + eax]
	ror	edx, 8
	.endr

#      tempa[0] =  tempa[0] ^ Rcon[i/Nk];
	mov	eax, ebx
	shr	eax, 2	# i/Nk
	xor	dl, [aes_128_Rcon + eax]
	#mov	[ebp], edx
#    }
1:
#    else if (Nk > 6 && i % Nk == 4)   ### Nk=4 so this is never executed
#    {
#      // Function Subword()
#      {
#        tempa[0] = getSBoxValue(tempa[0]);
#        tempa[1] = getSBoxValue(tempa[1]);
#        tempa[2] = getSBoxValue(tempa[2]);
#        tempa[3] = getSBoxValue(tempa[3]);
#      }
#    }

#    RoundKey[i * 4 + 0] = RoundKey[(i - Nk) * 4 + 0] ^ tempa[0];
#    RoundKey[i * 4 + 1] = RoundKey[(i - Nk) * 4 + 1] ^ tempa[1];
#    RoundKey[i * 4 + 2] = RoundKey[(i - Nk) * 4 + 2] ^ tempa[2];
#    RoundKey[i * 4 + 3] = RoundKey[(i - Nk) * 4 + 3] ^ tempa[3];

	mov	eax, [aes_128_RoundKey + ebx * 4 - Nk * 4]
	xor	eax, edx
	mov	[aes_128_RoundKey + ebx * 4], eax

	# verified	print "RoundKey "; push_	eax; call	_s_printhex8; call	newline

#  }
	inc	ebx
	jmp	0b
0:

	pop_	edi esi edx ecx ebx eax
	ret
#}




# This function adds the round key to state.
# The round key is added to the state by an XOR function.
#static void AddRoundKey(uint8_t round)
#{
#  uint8_t i,j;
#  for(i=0;i<4;++i)
#  {
#    for(j = 0; j < 4; ++j)
#    {
#      (*state)[i][j] ^= RoundKey[round * Nb * 4 + i * Nb + j];
#    }
#  }
#}
# in: al = round (byte)
# out: eax = al
aes_128_AddRoundKey:
	push_	ecx edx ebx
	movzx	eax, al
	mov	ebx, eax
	shl	ebx, 4	# round * Nb(=4) * 4

	xor	ecx, ecx
0:
	mov	edx, [aes_128_RoundKey + ebx + ecx * Nb] # +j : we get dword at once
	xor	[aes_128_state + ecx * 4], edx

	inc	ecx
	cmp	ecx, 4
	jb	0b

#		print "AddRoundKey: "
#		push	esi
#		mov	esi, offset aes_128_state
#		call	ph
#		pop	esi
	pop_	ebx edx ecx
	ret
	

# The SubBytes Function Substitutes the values in the
# state matrix with values in an S-box.
#static void SubBytes(void)
#{

# TODO: swap inner/outer loop for dword loop collapse
aes_128_SubBytes:
#  uint8_t i, j;
	push_	ecx edx eax
#  for(i = 0; i < 4; ++i)
#  {
	xor	ecx, ecx	# i
0:

#    for(j = 0; j < 4; ++j)
#    {
	xor	edx, edx	# j; we increment by 4
1:
#      (*state)[j][i] = getSBoxValue((*state)[j][i]);
	movzx	eax, byte ptr [aes_128_state + edx + ecx]
	mov	al, [aes_128_sbox + eax]
	mov	[aes_128_state + edx + ecx], al

#    }
	add	edx, 4
	cmp	edx, 16
	jb	1b

#  }
	inc	ecx
	cmp	ecx, 4
	jb	0b

	pop_	eax edx ecx
	ret
#}


#// The ShiftRows() function shifts the rows in the state to the left.
#// Each row is shifted with different offset.
#// Offset = Row number. So the first row is not shifted.
#static void ShiftRows(void)
#{
# TODO: maybe re-order state from column-major to row-major so we can replace code below with 3 rol opcodes
aes_128_ShiftRows:
#  uint8_t temp;
	push	eax
#
#  // Rotate first row 1 columns to left  
#  temp           = (*state)[0][1];
	mov	ah, [aes_128_state + 0*4 + 1]
#  (*state)[0][1] = (*state)[1][1];
	mov	al, [aes_128_state + 1*4 + 1]
	mov	[aes_128_state + 0*4 + 1], al
#  (*state)[1][1] = (*state)[2][1];
	mov	al, [aes_128_state + 2*4 + 1]
	mov	[aes_128_state + 1*4 + 1], al
#  (*state)[2][1] = (*state)[3][1];
	mov	al, [aes_128_state + 3*4 + 1]
	mov	[aes_128_state + 2*4 + 1], al
#  (*state)[3][1] = temp;
	mov	[aes_128_state + 3*4 + 1], ah
#
#  // Rotate second row 2 columns to left  
#  temp           = (*state)[0][2];
	mov	ah, [aes_128_state + 0*4 + 2]
#  (*state)[0][2] = (*state)[2][2];
	mov	al, [aes_128_state + 2*4 + 2]
	mov	[aes_128_state + 0*4 + 2], al
#  (*state)[2][2] = temp;
	mov	[aes_128_state + 2*4 + 2], ah
#
#  temp       = (*state)[1][2];
	mov	ah, [aes_128_state + 1*4 + 2]
#  (*state)[1][2] = (*state)[3][2];
	mov	al, [aes_128_state + 3*4 + 2]
	mov	[aes_128_state + 1*4 + 2], al
#  (*state)[3][2] = temp;
	mov	[aes_128_state + 3*4 + 2], ah
#
#  // Rotate third row 3 columns to left
#  temp       = (*state)[0][3];
	mov	ah, [aes_128_state + 0*4 + 3]
#  (*state)[0][3] = (*state)[3][3];
	mov	al, [aes_128_state + 3*4 + 3]
	mov	[aes_128_state + 0*4 + 3], al
#  (*state)[3][3] = (*state)[2][3];
	mov	al, [aes_128_state + 2*4 + 3]
	mov	[aes_128_state + 3*4 + 3], al
#  (*state)[2][3] = (*state)[1][3];
	mov	al, [aes_128_state + 1*4 + 3]
	mov	[aes_128_state + 2*4 + 3], al
#  (*state)[1][3] = temp;
	mov	[aes_128_state + 1*4 + 3], ah

	pop	eax
	ret
#}


#static uint8_t xtime(uint8_t x)
#{
#  return ((x<<1) ^ (((x>>7) & 1) * 0x1b));
#}
# in: al
# out: al
aes_128_xtime:
	# since x >> 7 is either 0 or 1, we then either:
	# - xor (x<<1) with 0x1b; or:
	# - x<<1 xor 0 == x<<1
	# Thus:
	push ebx
	mov	bl, al
	shl	al, 1
	shr	bl, 7
	jz	1f
	xor	al, 0x1b
1:	pop	ebx
	ret


#// MixColumns function mixes the columns of the state matrix
#static void MixColumns(void)
#{
aes_128_MixColumns:
	push_	eax edx ebx ecx edi
#  uint8_t i;
#  uint8_t Tmp,Tm,t;

#  for(i = 0; i < 4; ++i)
	xor	edi, edi
0:
#  {  
	mov	edx, [aes_128_state + edi]	# state[i][0..3]
#    t   = (*state)[i][0];
	mov	cl, dl	# t
#    Tmp = (*state)[i][0] ^ (*state)[i][1] ^ (*state)[i][2] ^ (*state)[i][3] ;
	mov	ebx, edx
	.rept 3
	xor	bh, bl
	shr	ebx, 8
	.endr
	xor	bl, bh	# Tmp

#    Tm  = (*state)[i][0] ^ (*state)[i][1] ; Tm = xtime(Tm);  (*state)[i][0] ^= Tm ^ Tmp ;
	mov	al, dl	#  state[i][0]
	xor	al, dh	# ^state[i][1]
	call	aes_128_xtime
	xor	al, bl		# Tm ^ Tmp
	xor	dl, al	# state[i][0] ^= 

#    Tm  = (*state)[i][1] ^ (*state)[i][2] ; Tm = xtime(Tm);  (*state)[i][1] ^= Tm ^ Tmp ;
	ror	edx, 8
	mov	al, dl	# state[i][1]
	xor	al, dh	# state[i][2]
	call	aes_128_xtime
	xor	al, bl		# Tm ^ Tmp
	xor	dl, al

#    Tm  = (*state)[i][2] ^ (*state)[i][3] ; Tm = xtime(Tm);  (*state)[i][2] ^= Tm ^ Tmp ;
	ror	edx, 8
	mov	al, dl	# state[i][2]
	xor	al, dh	# state[i][3]
	call	aes_128_xtime
	xor	al, bl		# Tm ^ Tmp
	xor	dl, al

#    Tm  = (*state)[i][3] ^ t ;        Tm = xtime(Tm);  (*state)[i][3] ^= Tm ^ Tmp ;
	ror	edx, 8
	mov	al, dl	# state[i][3]
	xor	al, cl	# t
	call	aes_128_xtime
	xor	al, bl	# Tm ^ Tmp
	xor	dl, al

	ror	edx, 8
	mov	[aes_128_state + edi], edx
#  }
	add	edi, 4
	cmp	edi, 16
	jb	0b

	pop_	edi ecx ebx edx eax
	ret
#}

# Multiply is used to multiply numbers in the field GF(2^8)
#if MULTIPLY_AS_A_FUNCTION
#static uint8_t Multiply(uint8_t x, uint8_t y)
#{
#  return (((y & 1) * x) ^
#       ((y>>1 & 1) * xtime(x)) ^
#       ((y>>2 & 1) * xtime(xtime(x))) ^
#       ((y>>3 & 1) * xtime(xtime(xtime(x)))) ^
#       ((y>>4 & 1) * xtime(xtime(xtime(xtime(x))))));
#  }
##else
##define Multiply(x, y)                                \
#      (  ((y & 1) * x) ^                              \
#      ((y>>1 & 1) * xtime(x)) ^                       \
#      ((y>>2 & 1) * xtime(xtime(x))) ^                \
#      ((y>>3 & 1) * xtime(xtime(xtime(x)))) ^         \
#      ((y>>4 & 1) * xtime(xtime(xtime(xtime(x))))))   \
#
##endif
# in: al = x
# in: dl = y
# out: al
aes_128_Multiply:
	push	edx
	xor	dh, dh	# dh = out

#       (((y & 1) * x) ^
	shr	dl, 1
	jnc	1f
	xor	dh, al	# out= 1 * x
1:	

#       ((y>>1 & 1) * xtime(x)) ^
#       ((y>>2 & 1) * xtime(xtime(x))) ^
#       ((y>>3 & 1) * xtime(xtime(xtime(x)))) ^
#       ((y>>4 & 1) * xtime(xtime(xtime(xtime(x))))));
	.rept 4
	call	aes_128_xtime	# al->xtime(al)
	shr	dl, 1
	jnc	1f
	xor	dh, al
1:
	.endr

	mov	al, dh
	pop	edx
	ret

# MixColumns function mixes the columns of the state matrix.
# The method used to multiply may be difficult to understand for the inexperienced.
# Please use the references to gain more information.
#static void InvMixColumns(void)
#{
#
aes_128_InvMixColumns:
#  int i;
#  uint8_t a,b,c,d;
	push_	eax edx ebx ecx edi
#  for(i=0;i<4;++i)
#  { 
	xor	edi, edi
0:

#    a = (*state)[i][0];
#    b = (*state)[i][1];
#    c = (*state)[i][2];
#    d = (*state)[i][3];
	mov	ecx, [aes_128_state + edi]	# a,b,c,d
	mov	edx, (0x0e) | (0x0b << 8) | (0x0d << 16) | (0x09 << 24)
	xor	ebx, ebx	# state[i] out

#    (*state)[i][0] = Multiply(a, 0x0e) ^ Multiply(b, 0x0b) ^ Multiply(c, 0x0d) ^ Multiply(d, 0x09);
#    (*state)[i][1] = Multiply(a, 0x09) ^ Multiply(b, 0x0e) ^ Multiply(c, 0x0b) ^ Multiply(d, 0x0d);
#    (*state)[i][2] = Multiply(a, 0x0d) ^ Multiply(b, 0x09) ^ Multiply(c, 0x0e) ^ Multiply(d, 0x0b);
#    (*state)[i][3] = Multiply(a, 0x0b) ^ Multiply(b, 0x0d) ^ Multiply(c, 0x09) ^ Multiply(d, 0x0e);
.rept 4
	mov	eax, ecx
	call	aes_128_Multiply
	xor	bl, al
	.rept 3
	shr	eax, 8	# al -> b
	ror	edx, 8	# constant shift: dl=0x0b
	call	aes_128_Multiply
	xor	bl, al
	.endr

	ror	ebx, 8	# state[i][0]

	# edx is ror-ed 24 bits, so rol-ed 8.
	# it was (hi->lo) 9, d, b, e
	# it now is:  d, b, e, 9; which is perfect.
	# another: b e 9 d
	# another: e 9 d b
.endr
	
	mov	[aes_128_state + edi], ebx
#  }
	add	edi, 4
	cmp	edi, 16
	jb	0b

	pop_	edi ecx ebx edx eax
	ret
#}


# The SubBytes function substitutes the values in the
# state matrix with values in an S-box.
#static void InvSubBytes(void)
#{
aes_128_InvSubBytes:
#  uint8_t i,j;
	push_	eax edx ecx
	xor	eax, eax	# saves on movzx
#  for(i=0;i<4;++i)
#  {
	xor	ecx, ecx
0:
#    for(j=0;j<4;++j)
#    {
	xor	edx, edx
1:

#      (*state)[j][i] = getSBoxInvert((*state)[j][i]);
	mov	al, [aes_128_state + edx + ecx]
	mov	al, [aes_128_rsbox + eax]
	mov	[aes_128_state + edx + ecx], al
#    }
	add	edx, 4
	cmp	edx, 16
	jb	1b
#  }
	inc	ecx
	cmp	ecx, 4
	jb	0b

	pop_	ecx edx eax
	ret
#}


#static void InvShiftRows(void)
#{
aes_128_InvShiftRows:
#  uint8_t temp;
	push_	eax ebx ecx edx
#
#  // Rotate first row 1 columns to right  
#  temp=(*state)[3][1];
	mov	ah, [aes_128_state + 3*4 + 1]

#  (*state)[3][1]=(*state)[2][1];
	mov	al, [aes_128_state + 2*4 + 1]
	mov	[aes_128_state + 3*4 + 1], al
#  (*state)[2][1]=(*state)[1][1];
	mov	al, [aes_128_state + 1*4 + 1]
	mov	[aes_128_state + 2*4 + 1], al
#  (*state)[1][1]=(*state)[0][1];
	mov	al, [aes_128_state + 0*4 + 1]
	mov	[aes_128_state + 1*4 + 1], al
#  (*state)[0][1]=temp;
	mov	[aes_128_state + 0*4 + 1], ah
#
#  // Rotate second row 2 columns to right 
#  temp=(*state)[0][2];
	mov	ah, [aes_128_state + 0*4 + 2]
#  (*state)[0][2]=(*state)[2][2];
	mov	al, [aes_128_state + 2*4 + 2]
	mov	[aes_128_state + 0*4 + 2], al
#  (*state)[2][2]=temp;
	mov	[aes_128_state + 2*4 + 2], ah
#
#  temp=(*state)[1][2];
	mov	ah, [aes_128_state + 1*4 + 2]
#  (*state)[1][2]=(*state)[3][2];
	mov	al, [aes_128_state + 3*4 + 2]
	mov	[aes_128_state + 1*4 + 2], al
#  (*state)[3][2]=temp;
	mov	[aes_128_state + 3*4 + 2], ah
#
#  // Rotate third row 3 columns to right
#  temp=(*state)[0][3];
	mov	ah, [aes_128_state + 0*4 + 3]
#  (*state)[0][3]=(*state)[1][3];
	mov	al, [aes_128_state + 1*4 + 3]
	mov	[aes_128_state + 0*4 + 3], al
#  (*state)[1][3]=(*state)[2][3];
	mov	al, [aes_128_state + 2*4 + 3]
	mov	[aes_128_state + 1*4 + 3], al
#  (*state)[2][3]=(*state)[3][3];
	mov	al, [aes_128_state + 3*4 + 3]
	mov	[aes_128_state + 2*4 + 3], al
#  (*state)[3][3]=temp;
	mov	[aes_128_state + 3*4 + 3], ah

	pop_	edx ecx ebx eax 
	ret
#}


# Cipher is the main function that encrypts the PlainText.
#static void Cipher(void)
aes_128_Cipher:
#{
#  uint8_t round = 0;
	push_	eax
	xor	eax, eax
#
#  // Add the First round key to the state before starting the rounds.
#  AddRoundKey(0); 
	call	aes_128_AddRoundKey	# al is 0
#  
#  // There will be Nr rounds.
#  // The first Nr-1 rounds are identical.
#  // These Nr-1 rounds are executed in the loop below.
#  for(round = 1; round < Nr; ++round)
#  {
	.rept Nr-1
#    SubBytes();
	call	aes_128_SubBytes
#    ShiftRows();
	call	aes_128_ShiftRows
#    MixColumns();
	call	aes_128_MixColumns
#    AddRoundKey(round);
	inc	al
	call	aes_128_AddRoundKey
	.endr
#  }
#  
#  // The last round is given below.
#  // The MixColumns function is not here in the last round.
#  SubBytes();
	call	aes_128_SubBytes
#  ShiftRows();
	call	aes_128_ShiftRows
#  AddRoundKey(Nr);
	inc	al	# becomes Nr
	call	aes_128_AddRoundKey

	pop_	eax
	ret
#}



#static void InvCipher(void)
aes_128_InvCipher:
#{
#  uint8_t round=0;
	push_	eax
#
#  // Add the First round key to the state before starting the rounds.
#  AddRoundKey(Nr); 
	mov	al, Nr
	call	aes_128_AddRoundKey
#
#  // There will be Nr rounds.
#  // The first Nr-1 rounds are identical.
#  // These Nr-1 rounds are executed in the loop below.
#  for(round=Nr-1;round>0;round--)
#  {
	.rept Nr-1
#    InvShiftRows();
	call	aes_128_InvShiftRows
#    InvSubBytes();
	call	aes_128_InvSubBytes
#    AddRoundKey(round);
	dec	al
	call	aes_128_AddRoundKey
#    InvMixColumns();
	call	aes_128_InvMixColumns
	.endr
#  }
#  
#  // The last round is given below.
#  // The MixColumns function is not here in the last round.
#  InvShiftRows();
	call	aes_128_InvShiftRows
#  InvSubBytes();
	call	aes_128_InvSubBytes
#  AddRoundKey(0);
	xor	al, al	# dec al should also give 0
	call	aes_128_AddRoundKey
	pop_	eax
	ret
#}


#// This can be replaced with a call to memcpy
#static void BufferCopy(uint8_t* output, uint8_t* input)
#{
#  uint8_t i;
#  for (i=0;i<16;++i)
#  {
#    output[i] = input[i];
#  }
#}

# in: esi
# in: edi
aes_128_BufferCopy:
	push_	ecx esi edi
	mov	ecx, 16/4
	rep	movsd
	pop_	edi esi ecx
	ret



/*****************************************************************************/
/* Public functions:                                                         */
/*****************************************************************************/

#void AES128_ECB_encrypt(uint8_t* input, const uint8_t* key, uint8_t* output)
# in: esi = input
# in: edi = output
# in: ebx = key

aes_128_ecb_crypt_setup$:
#{
#  // Copy input to output, and work in-memory on output
#  BufferCopy(output, input);
	movsd
	movsd
	movsd
	movsd
	sub	edi, 16
	sub	esi, 16
	
#  state = (state_t*)output;
	push_	esi edi
	mov	esi, edi	# output
	mov	edi, offset aes_128_state
	movsd
	movsd
	movsd
	movsd
	pop_	edi esi

#  // The KeyExpansion routine must be called before encryption.
#  Key = key;
	mov	[aes_128_Key], ebx
#  KeyExpansion();
	call	aes_128_KeyExpansion

	ret

aes_128_encrypt:
	call	aes_128_ecb_crypt_setup$
#  // The next function call encrypts the PlainText with the Key using AES algorithm.
#  Cipher();
	call	aes_128_Cipher

	# we used internal state so copy to output:
	push_	esi edi
	mov	esi, offset aes_128_state
	movsd
	movsd
	movsd
	movsd
	pop_	edi esi
	ret
#}

#void AES128_ECB_decrypt(uint8_t* input, const uint8_t* key, uint8_t *output)
aes_128_decrypt:
	call	aes_128_ecb_crypt_setup$
#{
#  // Copy input to output, and work in-memory on output
#  BufferCopy(output, input);
#  state = (state_t*)output;
#
#  Key = key;
#  KeyExpansion();
#
#  InvCipher();
	call	aes_128_InvCipher
	# we used internal state so copy to output:
	push_	esi edi
	mov	esi, offset aes_128_state
	movsd
	movsd
	movsd
	movsd
	pop_	edi esi
	ret
#}


aes_128_test:
	printlnc 11, "Testing AES-128-CBC"
	LOAD_TXT "Hello World!3456"		# input: 16 bytes
	LOAD_TXT "1234567890123456", ebx	# key 16 bytes = 128 bits
	mov	edi, offset test_encrypt_output
	call	aes_128_encrypt
	print "Encrypted: "
	call	1f
	# test decrypt
	mov	esi, offset test_encrypt_output
	mov	edi, offset test_decrypt_output
	# ebx=key unchanged
	call	aes_128_decrypt
	print "Decrypted: "
	call	1f
	mov	esi,edi
	mov	ecx, 16
	call	nprintln
	ret

1:	mov	esi, edi
	mov	ecx, 16
0:	lodsb
	mov	dl, al
	call	printhex2
	call	printspace
	loop	0b
	call	newline
	ret

.data SECTION_DATA_BSS
test_encrypt_output: .space 16
test_decrypt_output: .space 16
