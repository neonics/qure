;²²²²²²²²²²²²²²²²²²²²²²²²²²²²²²²  MD5 Library  ²²²²²²²²²²²²²²²²²²²²²²²²²²²²²²²²
;
;       CopyRight (c) 1996 by Kenney Westerhof AKA Kenney Knuman AKA Forge
;
;       MD5 Message Digest hashing routines 0.10á
;
;
;

Lib_Name        EQU 'MD5 Library'
Lib_Version     EQU '0.10á'
Lib_Copyright   EQU 'Copyright (C) 1996 by Kenney Westerhof AKA Kenney Knuman AKA Forge'


; °°°°±±±±±±±±±²²²²²²²²²²²²ÛÛÛÛÛÛÛßßßßßßßßßßßßßÛÛÛÛÛÛÛ²²²²²²²²²²²²±±±±±±±±±°°°°
; °°°°±±±±±±±±±²²²²²²²²²²²²ÛÛÛÛÛÛÛ             ÛÛÛÛÛÛÛ²²²²²²²²²²²²±±±±±±±±±°°°°
; °°°°±±±±±±±±±²²²²²²²²²²²²ÛÛÛÛÛÛÛ   PUBLICS   ÛÛÛÛÛÛÛ²²²²²²²²²²²²±±±±±±±±±°°°°
; °°°°±±±±±±±±±²²²²²²²²²²²²ÛÛÛÛÛÛÛ             ÛÛÛÛÛÛÛ²²²²²²²²²²²²±±±±±±±±±°°°°
; °°°°±±±±±±±±±²²²²²²²²²²²²ÛÛÛÛÛÛÛÜÜÜÜÜÜÜÜÜÜÜÜÜÛÛÛÛÛÛÛ²²²²²²²²²²²²±±±±±±±±±°°°°

PUBLiC  MD5_Init, MD5_Update, MD5_Final


; °°°°±±±±±±±±±²²²²²²²²²²²²ÛÛÛÛÛÛÛßßßßßßßßßßßßßÛÛÛÛÛÛÛ²²²²²²²²²²²²±±±±±±±±±°°°°
; °°°°±±±±±±±±±²²²²²²²²²²²²ÛÛÛÛÛÛÛ             ÛÛÛÛÛÛÛ²²²²²²²²²²²²±±±±±±±±±°°°°
; °°°°±±±±±±±±±²²²²²²²²²²²²ÛÛÛÛÛÛÛ     CODE    ÛÛÛÛÛÛÛ²²²²²²²²²²²²±±±±±±±±±°°°°
; °°°°±±±±±±±±±²²²²²²²²²²²²ÛÛÛÛÛÛÛ             ÛÛÛÛÛÛÛ²²²²²²²²²²²²±±±±±±±±±°°°°
; °°°°±±±±±±±±±²²²²²²²²²²²²ÛÛÛÛÛÛÛÜÜÜÜÜÜÜÜÜÜÜÜÜÛÛÛÛÛÛÛ²²²²²²²²²²²²±±±±±±±±±°°°°

		.386
		locals
		jumps

                Assume  cs:CryptCode, ds:nothing

CryptCode       Segment Word USE16 Public 'Code'

                db Lib_Name, 'Version  ', Lib_Version, Lib_Copyright,0

;       These arrays are put in the code segment so there can be a CS: override.
Padding         db 80h, 63 dup(0)
Input           dd 16 dup(0)
Buf             dd 4 dup(0)     ;a,b,c,d

MD5_CTX         Struc
                ScratchBuf      dd 4 dup(0)
                BitsHandled     dd 2 dup(0)
                InputBuf        db 64 dup(0)
                EndS


;in: ds:si pointer to ctx struc
MD5_Init        Proc Far
                push    eax
                xor     eax,eax
                mov     [si.BitsHandled],eax
                mov     [si.BitsHandled+4],eax

                ; Load magic initialization constants.
                mov     [si.ScratchBuf+00], 067452301h  ;stored as 01234567
                mov     [si.ScratchBuf+04], 0efcdab89h  ;          89abcdef
                mov     [si.ScratchBuf+08], 098badcfeh  ;          fedcba98
                mov     [si.ScratchBuf+12], 010325476h  ;          76543210

        q=0
        Rept    16
                mov     dword ptr [si.InputBuf+q],eax
                q=q+4
        EndM
                pop     eax
                ret
MD5_Init        EndP



;in: ds:si=ctx pointer, es:di=string, ecx=stringlen
MD5_Update      Proc Far
                push    bx eax di
                mov     ebx,[si.BitsHandled]
                shr     ebx,3
                and     bx,3fh

                mov     eax,ecx
                shl     eax,3
                add     eax,[si.BitsHandled]
                cmp     eax,[si.BitsHandled]
                jae     @@Nah0
                inc     [si.BitsHandled+4]
@@Nah0:
                mov     eax,ecx
                shl     eax,3
                add     [si.BitsHandled],eax
                mov     eax,ecx
                shr     eax,29
                add     [si.BitsHandled+4],eax

                or      cx,cx
                jz      @@Skip
@@0:
                mov     al,es:[di]
                inc     di
                mov     [bx+si.InputBuf],al
                inc     bx

                cmp     bx,64
                jnz     @@Nah1

                
                push    cx
                mov     cx,16
                xor     bx,bx
@@1:            mov     eax,dword ptr [si.InputBuf+bx]
                mov     [bx+Input],eax
                add     bx,4          
                loop    @@1
                pop     cx

;             Transform (mdContext->buf, in);
                call    Transform
                xor     bx,bx           ;mdi=0

@@Nah1:
                loop    @@0
@@SKip:

                pop     di eax bx
                ret
MD5_Update      EndP


;in: ds:si pointer to md5_ctx, es:di pointer to the digest
MD5_Final       Proc Far
                push    eax ebx ecx ebp

                mov     ebx,[si.BitsHandled]
                mov     [Input+14*4],ebx
                mov     eax,[si.BitsHandled+4]
                mov     [Input+15*4],eax

                shr     ebx,3
                and     ebx,3fh         ;bx=mdi

                cmp     bx,56
                jge     @@Yo
                mov     eax,56
                sub     ax,bx
                jmp     @@yo1
@@Yo:           mov     eax,120
                sub     ax,bx
@@yo1:          mov     ebp,eax           ;bp=padlen


                push    es di
;in: ds:si=ctx pointer, es:di=string, ecx=stringlen
;ds:si staat nog goed op mdContext (is een ctx pointer)
                mov     ecx,ebp
                mov     di,seg Padding
                mov     es,di
                mov     di,offset Padding
                call    MD5_Update
                pop     di es


                push    cx bx
                xor     cx,cx           ;i [0..14]
                mov     cx,14
                xor     bx,bx
@@1:            mov     eax,dword ptr [si.InputBuf+bx]
                mov     [bx+Input],eax

                add     bx,4
                loop    @@1
                pop     bx cx

                call    Transform

                mov     eax,[si.ScratchBuf+0]
                mov     es:[di],eax
                mov     eax,[si.ScratchBuf+4]
                mov     es:[di+4],eax
                mov     eax,[si.ScratchBuf+8]
                mov     es:[di+8],eax
                mov     eax,[si.ScratchBuf+12]
                mov     es:[di+12],eax

                pop     ebp ecx ebx eax
                ret
MD5_Final       EndP




;in: x,y,z. Uses eax ebx. Out: eax
F               Macro   x,y,z
                mov     eax,x
                mov     ebx,eax
                and     eax,y
                not     ebx
                and     ebx,z
                or      eax,ebx
                EndM

;in: x,y,z, out: eax, uses eax ebx
G               Macro   x,y,z
                mov     eax,z
                mov     ebx,eax
                and     eax,x
                not     ebx
                and     ebx,y
                or      eax,ebx
                EndM

;in: x,y,z. Out: eax, uses eax
H               Macro   x,y,z
                mov     eax,x
                xor     eax,y
                xor     eax,z
                EndM

;in: x,y,z. Out: eax, uses eax
I               Macro   x,y,z
                mov     eax,z
                not     eax
                or      eax,x
                xor     eax,y
                EndM


FF              Macro   aa,bb,cc,dd,xx,s,ac
                F       bb,cc,dd
                add     eax,xx
                add     eax,ac
                add     eax,aa
                rol     eax,s
                add     eax,bb
                mov     aa,eax
                EndM

GG              Macro   aa,bb,cc,dd,xx,s,ac
                G       bb,cc,dd
                add     eax,xx
                add     eax,ac
                add     eax,aa
                rol     eax,s
                add     eax,bb
                mov     aa,eax
                EndM

HH              Macro   aa,bb,cc,dd,xx,s,ac
                H       bb,cc,dd
                add     eax,xx
                add     eax,ac
                add     eax,aa
                rol     eax,s
                add     eax,bb
                mov     aa,eax
                EndM

II              Macro   aa,bb,cc,dd,xx,s,ac
                I       bb,cc,dd
                add     eax,xx
                add     eax,ac
                add     eax,aa
                rol     eax,s
                add     eax,bb
                mov     aa,eax
                EndM



;de *buf wordt als eerste gecopied: [si.ScratchBuf] is *buf, en
;de a, b, c en d zit in de var buf  dd 4 dup (0) bovenaan.

;  register UINT4 a = buf[0], b = buf[1], c = buf[2], d = buf[3];
; ik rip dus uit *buf de buf[0..3] en die dump ik in mijn local var buf
;want *buf is eigenlijk ScratchBuf. dus:
;  register UINT4 a = scratchbuf[0], b = scratchbuf[1],..

a       EQU [buf+0]
b       EQU [buf+4]
c       EQU [buf+8]
d       EQU [buf+12]
;in: ds:si pointer to ctx buf
Transform       Proc Near
                push    eax ebx

                mov     eax,[si.ScratchBuf]
                mov     a,eax
                mov     eax,[si.ScratchBuf+4]
                mov     b,eax
                mov     eax,[si.ScratchBuf+8]
                mov     c,eax
                mov     eax,[si.ScratchBuf+12]
                mov     d,eax

;  /* Round 1 */
s11     = 7
s12     = 12
s13     = 17
s14     = 22

FF  a, b, c, d, [Input+0*4],  S11, 0D76AA478h; /* 1 */
FF  d, a, b, c, [Input+1*4],  S12, 0E8C7B756h; /* 2 */
FF  c, d, a, b, [Input+2*4],  S13, 0242070DBh; /* 3 */
FF  b, c, d, a, [Input+3*4],  S14, 0C1BDCEEEh; /* 4 */
FF  a, b, c, d, [Input+4*4],  S11, 0F57C0FAFh; /* 5 */
FF  d, a, b, c, [Input+5*4],  S12, 04787C62Ah; /* 6 */
FF  c, d, a, b, [Input+6*4],  S13, 0A8304613h; /* 7 */
FF  b, c, d, a, [Input+7*4],  S14, 0FD469501h; /* 8 */
FF  a, b, c, d, [Input+8*4],  S11, 0698098D8h; /* 9 */
FF  d, a, b, c, [Input+9*4],  S12, 08B44F7AFh; /* 10 */
FF  c, d, a, b, [Input+10*4], S13, 0FFFF5BB1h; /* 11 */
FF  b, c, d, a, [Input+11*4], S14, 0895CD7BEh; /* 12 */
FF  a, b, c, d, [Input+12*4], S11, 06B901122h; /* 13 */
FF  d, a, b, c, [Input+13*4], S12, 0FD987193h; /* 14 */
FF  c, d, a, b, [Input+14*4], S13, 0A679438Eh; /* 15 */
FF  b, c, d, a, [Input+15*4], S14, 049B40821h; /* 16 */


;  /* Round 2 */
s21     =  5
s22     =  9
s23     = 14
s24     = 20

GG  a, b, c, d, [Input+4*1],  S21, 0F61E2562h; /* 17 */
GG  d, a, b, c, [Input+4*6],  S22, 0C040B340h; /* 18 */
GG  c, d, a, b, [Input+4*11], S23, 0265E5A51h; /* 19 */
GG  b, c, d, a, [Input+4*0],  S24, 0E9B6C7AAh; /* 20 */
GG  a, b, c, d, [Input+4*5],  S21, 0D62F105Dh; /* 21 */
GG  d, a, b, c, [Input+4*10], S22, 002441453h; /* 22 */
GG  c, d, a, b, [Input+4*15], S23, 0D8A1E681h; /* 23 */
GG  b, c, d, a, [Input+4*4],  S24, 0E7D3FBC8h; /* 24 */
GG  a, b, c, d, [Input+4*9],  S21, 021E1CDE6h; /* 25 */
GG  d, a, b, c, [Input+4*14], S22, 0C33707D6h; /* 26 */
GG  c, d, a, b, [Input+4*3],  S23, 0F4D50D87h; /* 27 */
GG  b, c, d, a, [Input+4*8],  S24, 0455A14EDh; /* 28 */
GG  a, b, c, d, [Input+4*13], S21, 0A9E3E905h; /* 29 */
GG  d, a, b, c, [Input+4*2],  S22, 0FCEFA3F8h; /* 30 */
GG  c, d, a, b, [Input+4*7],  S23, 0676F02D9h; /* 31 */
GG  b, c, d, a, [Input+4*12], S24, 08D2A4C8Ah; /* 32 */

;  /* Round 3 */
S31     =  4
S32     = 11
S33     = 16
S34     = 23

HH  a, b, c, d, [Input+4*5],  S31, 0FFFA3942h; /* 33 */
HH  d, a, b, c, [Input+4*8],  S32, 08771F681h; /* 34 */
HH  c, d, a, b, [Input+4*11], S33, 06D9D6122h; /* 35 */
HH  b, c, d, a, [Input+4*14], S34, 0FDE5380Ch; /* 36 */
HH  a, b, c, d, [Input+4*1],  S31, 0A4BEEA44h; /* 37 */
HH  d, a, b, c, [Input+4*4],  S32, 04BDECFA9h; /* 38 */
HH  c, d, a, b, [Input+4*7],  S33, 0F6BB4B60h; /* 39 */
HH  b, c, d, a, [Input+4*10], S34, 0BEBFBC70h; /* 40 */
HH  a, b, c, d, [Input+4*13], S31, 0289B7EC6h; /* 41 */
HH  d, a, b, c, [Input+4*0],  S32, 0EAA127FAh; /* 42 */
HH  c, d, a, b, [Input+4*3],  S33, 0D4EF3085h; /* 43 */
HH  b, c, d, a, [Input+4*6],  S34, 004881D05h; /* 44 */
HH  a, b, c, d, [Input+4*9],  S31, 0D9D4D039h; /* 45 */
HH  d, a, b, c, [Input+4*12], S32, 0E6DB99E5h; /* 46 */
HH  c, d, a, b, [Input+4*15], S33, 01FA27CF8h; /* 47 */
HH  b, c, d, a, [Input+4*2],  S34, 0C4AC5665h; /* 48 */


;  /* Round 4 */
S41     =  6
S42     = 10
S43     = 15
S44     = 21

II  a, b, c, d, [Input+4*0],  S41, 0F4292244h; /* 49 */
II  d, a, b, c, [Input+4*7],  S42, 0432AFF97h; /* 50 */
II  c, d, a, b, [Input+4*14], S43, 0AB9423A7h; /* 51 */
II  b, c, d, a, [Input+4*5],  S44, 0FC93A039h; /* 52 */
II  a, b, c, d, [Input+4*12], S41, 0655B59C3h; /* 53 */
II  d, a, b, c, [Input+4*3],  S42, 08F0CCC92h; /* 54 */
II  c, d, a, b, [Input+4*10], S43, 0FFEFF47Dh; /* 55 */
II  b, c, d, a, [Input+4*1],  S44, 085845DD1h; /* 56 */
II  a, b, c, d, [Input+4*8],  S41, 06FA87E4Fh; /* 57 */
II  d, a, b, c, [Input+4*15], S42, 0FE2CE6E0h; /* 58 */
II  c, d, a, b, [Input+4*6],  S43, 0A3014314h; /* 59 */
II  b, c, d, a, [Input+4*13], S44, 04E0811A1h; /* 60 */
II  a, b, c, d, [Input+4*4],  S41, 0F7537E82h; /* 61 */
II  d, a, b, c, [Input+4*11], S42, 0BD3AF235h; /* 62 */
II  c, d, a, b, [Input+4*2],  S43, 02AD7D2BBh; /* 63 */
II  b, c, d, a, [Input+4*9],  S44, 0EB86D391h; /* 64 */


                mov     eax,a
                add     [si.ScratchBuf],eax
                mov     eax,b
                add     [si.ScratchBuf+4],eax
                mov     eax,c
                add     [si.ScratchBuf+8],eax
                mov     eax,d
                add     [si.ScratchBuf+12],eax

                pop     ebx eax
                ret
Transform       EndP

CryptCode       EndS


                End
