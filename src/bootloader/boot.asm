; Location for memory
org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

; FAT12 header
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880
bdb_media_desc_type:  db 0F0h
bdb_sectors_per_fat:        dw 9
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; Extended boot record
ebr_drive_number:           db 0 
                            db 0
ebr_sig:                    db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h
ebr_volume_label:           db "MERCURY OS"
ebr_system_id:              db "FAT12   "

start:
    jmp main

; Prints a string to the screen
; Parameters:
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

    mov [ebr_drive_number], dl
    mov ax, 1
    mov cl, 1
    mov bx, 0x7E00
    call disk_read

    mov si, msg_start
    call puts

    cli
    hlt

disk_read_err:
    mov si, msg_disk_read_err
    call puts
    jmp wait_key_and_reboot
wait_key_and_reboot:
    mov ah, 0
    int 16h
    jmp 0FFFFh:0

.halt:
    cli
    hlt

; Disk routines

; Converts an LBA address to a CHS address
; Parameters:
;   - ax: LBA address
; Return:
;   - cx [bits 0-5]: sector number
;   - cx [bits 6-15]: cylinder
;   - dh: head
lba_to_chs:
    push ax
    push dx

    xor dx, dx ; dx = 0
    div word [bdb_sectors_per_track]
    inc dx
    mov cx, dx
    xor dx, dx
    div word [bdb_heads]
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah

    pop ax
    mov dl, al
    pop ax
    ret

; Reads sectors from a disk
; Parameters:
;   - ax: LBA address
;   - cl: Number of sectors to read (0-128)
;   - dl: Drive number
;   - es:bx: Memory address where to store read data
disk_read:
    push ax
    push bx
    push cx
    push dx
    push di
    push cx
    call lba_to_chs
    pop ax 
    mov ah, 02h
    mov di, 3
.retry:
    pusha
    stc
    int 13h
    jnc .done
    popa
    call disk_reset
    dec di
    test di, di
    jnz .retry
.fail:
    jmp disk_read_err
.done:
    popa
    pop di
    pop dx
    pop cx
    pop bx
    pop ax 
    ret

; Reset disk controller
; Parameters:
;   dl: Drive number
disk_reset:
    pusha
    mov ah, 0 
    stc
    int 13h
    jc disk_read_err
    popa
    ret
     
msg_disk_read_err: db 'Read from disk failed', ENDL, 0
msg_start: db 'MercuryOS', ENDL, 0

; Fill rest of data up to 510 bytes with 0s
times 510-($-$$) db 0
; Magic code for compiler (2 bytes long)
dw 0AA55h