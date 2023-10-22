bits 16

section _TEXT class=CODE

global _x86_Div64_32
_x86_Div64_32:
    push bp
    mov bp, sp

    push bx

    mov eax, [bp + 8]
    mov ecx, [bp + 12]
    xor edx, edx
    div ecx

    mov bx, [bp + 16]
    mov [bx + 4], eax

    mov eax, [bp + 4]
    div ecx

    mov [bx], eax
    mov bx, [bp + 18]
    mov [bx], edx

    pop bx

    mov sp, bp
    pop bp
    ret

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