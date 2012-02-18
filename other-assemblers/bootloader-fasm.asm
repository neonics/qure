start:
      mov ax, 0xb800
      mov es,ax
      mov [es:0], byte 'A'  ;0x41
      mov [es:1], byte 0x1f
loop1: jmp loop1

#db 144 * 10240 - $  dup 0
