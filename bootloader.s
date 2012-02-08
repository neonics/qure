.intel_syntax noprefix

.text
.code16
.global start
start:
      mov	ax, 0xb800
      mov	es,ax
      xor	di, di
      mov	al, 0x41
      stosb
      mov	al, 0x1f
      stosb
#      mov [byte ptr es:0], 0x41
#      mov [byte ptr es:1], 0x1f
loop1: jmp loop1

.align 512, 0
