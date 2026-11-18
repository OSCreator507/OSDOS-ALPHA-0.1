; boot.asm - Загрузчик для OSDOS 1.0
BITS 16
ORG 0x7C00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [boot_drive], dl

    mov si, msg_loading
    call print_string

    ; Загрузка ядра по адресу 0x1000:0000
    mov ax, 0x1000
    mov es, ax
    xor bx, bx
    
    mov ah, 0x02
    mov al, 8           ; Читаем 8 секторов (4 КБ) - этого хватит для ядра
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    mov si, msg_loaded
    call print_string

    jmp 0x1000:0000

disk_error:
    mov si, msg_error
    call print_string
    jmp $

print_string:
    push ax
    push bx
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07
.loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .loop
.done:
    pop bx
    pop ax
    ret

boot_drive  db 0
msg_loading db "OSDOS 1.0 booting...", 13, 10, 0
msg_loaded  db "Kernel loaded! Jumping...", 13, 10, 0
msg_error   db "Disk read error!", 13, 10, 0

times 510-($-$$) db 0
dw 0xAA55