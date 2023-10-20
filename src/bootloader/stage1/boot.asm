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
    ; Setup data segments
    mov ax, 0 ; Write to ax because ds/es cannot be accessed directly
    mov ds, ax
    mov es, ax

    ; Setup stack
    mov ss, ax
    mov sp, 0x7C00 ; Set stack pointer to the start of memory

    push es
    push word .after
    retf

.after:
    mov [ebr_drive_number], dl

    mov si, msg_loading
    call puts

    ; Read drive parameters (sectors per track and head count),
    push es
    mov ah, 08h
    int 13h
    jc err_disk_read
    pop es

    and cl, 0x3F
    xor ch, ch
    mov [bdb_sectors_per_track], cx

    inc dh
    mov [bdb_heads], dh

    ; Compute LBA of root directory = reserved + fats * sectors_per_fat
    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx
    add ax, [bdb_reserved_sectors]
    push ax

    ; Compute size of root directory = (32 * number_of_entries) / bytes_per_sector
    mov ax, [bdb_dir_entries_count]
    shl ax, 5
    xor dx, dx
    div word [bdb_bytes_per_sector]

    test dx, dx
    jz .root_dir_after
    inc ax
.root_dir_after:

    ; read root directory
    mov cl, al                          ; cl = number of sectors to read = size of root directory
    pop ax                              ; ax = LBA of root directory
    mov dl, [ebr_drive_number]          ; dl = drive number (we saved it previously)
    mov bx, buffer                      ; es:bx = buffer
    call disk_read

    ; search for kernel.bin
    xor bx, bx
    mov di, buffer

.search_kernel:
    mov si, stage2_file
    mov cx, 11                          ; compare up to 11 characters
    push di
    repe cmpsb
    pop di
    je .found_kernel

    add di, 32
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_kernel

    ; kernel not found
    jmp err_stage2_not_found

.found_kernel:

    ; di should have the address to the entry
    mov ax, [di + 26]                   ; first logical cluster field (offset 26)
    mov [stage2_cluster], ax

    ; load FAT from disk into memory
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    ; Read kernel and process FAT chain
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET
.load_kernel_loop:
    ; Read next cluster
    mov ax, [stage2_cluster]
    
    add ax, 31
    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]

    ; Compute location of next cluster
    mov ax, [stage2_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx

    mov si, buffer
    add si, ax
    mov ax, [ds:si]

    or dx, dx
    jz .even

.odd:
    shr ax, 4
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0x0FF8
    jae .read_finish

    mov [stage2_cluster], ax
    jmp .load_kernel_loop

.read_finish:
    mov dl, [ebr_drive_number]

    mov ax, KERNEL_LOAD_SEGMENT
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    jmp wait_key_and_reboot

    cli
    hlt

err_disk_read:
    mov si, msg_disk_read_err
    call puts
    jmp wait_key_and_reboot

err_stage2_not_found:
    mov si, msg_stage2_not_found_err
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h
    jmp 0FFFFh:0

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
    jmp err_disk_read
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
    jc err_disk_read
    popa
    ret
disk_reset_err:
    cli
    hlt
    
     
msg_disk_read_err: db 'Read from disk failed', ENDL, 0
msg_stage2_not_found_err: db 'STAGE2 not found!', ENDL, 0

msg_loading: db 'Loading...', ENDL, 0

stage2_file: db 'STAGE2  BIN', ENDL, 0

stage2_cluster: dw 0

KERNEL_LOAD_SEGMENT equ 0x2000
KERNEL_LOAD_OFFSET equ 0

; Fill rest of data up to 510 bytes with 0s
times 510-($-$$) db 0
; Magic code for compiler (2 bytes long)
dw 0AA55h

buffer: