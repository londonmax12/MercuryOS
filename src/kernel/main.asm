; Location for memory
org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

start:
    jmp main

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

main:
    ; Setup data segments
    mov ax, 0 ; Write to ax because ds/es cannot be accessed directly
    mov ds, ax
    mov es, ax

    ; Setup stack
    mov ss, ax
    mov sp, 0x7C00 ; Set stack pointer to the start of memory

    mov si, hello_world
    call puts

    hlt

.halt:
    jmp .halt

hello_world: db 'Hello World!', ENDL, 0

; Fill rest of data up to 510 bytes with 0s
times 510-($-$$) db 0
; Magic code for compiler (2 bytes long)
dw 0AA55h