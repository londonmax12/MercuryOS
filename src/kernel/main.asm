; Location for memory
org 0x0
bits 16

%define ENDL 0x0D, 0x0A

start:
    mov si, hello_world
    call puts
.halt:
    cli
    hlt


; Prints a string to the screen
; Params:
;   - ds:si - pointer to string
puts:
    ; Store values that are modified
    push si
    push ax
    push bx
.loop:
    lodsb ; Load next char into al
    or al, al ; Check if the next character is null
    jz .done ; If next char is null go to done

    mov ah, 0x0e
    mov bh, 0
    int 0x10 ; Call bios interrupt

    jmp .loop ; Go back to loop if char is not null
.done:
    pop bx
    pop ax
    pop si    
    ret


.halt:
    jmp .halt

hello_world: db 'MercuryOS', ENDL, 0

; Fill rest of data up to 510 bytes with 0s
times 510-($-$$) db 0
; Magic code for compiler (2 bytes long)
dw 0AA55h