bits 16

section _TEXT class=CODE

; int 10h ah=0Eh
; args: char, page
global _x86_Video_WriteCharTeletype
_x86_Video_WriteCharTeletype:
    ; Make new call frame
    push bp ; Return address
    mov bp, sp

    push bx

    mov ah, 0Eh
    mov al, [bp + 4] ; First argument
    mov bh, [bp + 6] ; Second parameter

    int 10h

    pop bx

    mov sp, bp
    pop bp
    ret