; kernel.asm - Ядро OSDOS 1.0 (Проверка существования дисков)
BITS 16
ORG 0x0000

start:
    ; Настройка сегментов
    mov ax, 0x1000
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFF

    ; Очищаем экран при старте
    call clear_screen

    ; Приветствие
    mov si, msg_welcome
    call print_string

shell_loop:
    ; Собираем и выводим приглашение (например, OSDOS A:\>)
    call build_prompt
    mov si, prompt_buffer
    call print_string

    ; Читаем строку от пользователя
    call read_string
    
    ; Проверяем, что ввели
    call check_command
    
    ; Возвращаемся к началу цикла
    jmp shell_loop

; =========================================================
; Обработка команд
; =========================================================
check_command:
    ; Разбиваем строку на команду и аргумент
    mov si, cmd_buffer
    mov di, command_str
.parse_cmd:
    mov al, [si]
    cmp al, ' '
    je .found_space
    cmp al, 0
    je .end_cmd
    mov [di], al
    inc di
    inc si
    jmp .parse_cmd
.found_space:
    mov byte [di], 0
    inc si
    mov di, argument_str
.copy_arg:
    mov al, [si]
    mov [di], al
    inc di
    inc si
    cmp al, 0
    jne .copy_arg
    jmp .check_cmds
.end_cmd:
    mov byte [di], 0
    mov byte [argument_str], 0

.check_cmds:
    ; 1. Проверка на пустую строку
    cmp byte [command_str], 0
    je .done

    ; 2. Команда "HELP"
    mov si, command_str
    mov di, cmd_help
    call strcmp
    jc .do_help

    ; 3. Команда "CLEAR"
    mov si, command_str
    mov di, cmd_clear
    call strcmp
    jc .do_clear

    ; 4. Команда "DIR"
    mov si, command_str
    mov di, cmd_dir
    call strcmp
    jc .do_dir

    ; 5. Команда "CD"
    mov si, command_str
    mov di, cmd_cd
    call strcmp
    jc .do_cd

    ; Если ничего не совпало - ошибка
    mov si, msg_unknown
    call print_string
    jmp .done

.do_help:
    mov si, msg_help_text
    call print_string
    jmp .done

.do_clear:
    call clear_screen
    jmp .done

.do_dir:
    call build_dir_path
    mov si, prompt_buffer
    call print_string
    mov si, msg_dir_files
    call print_string
    jmp .done

.do_cd:
    ; Если аргумента нет, ничего не делаем
    cmp byte [argument_str], 0
    je .done

    ; Проверка на "cd X:" (смена диска)
    cmp byte [argument_str + 1], ':'
    jne .not_cd_drive
    cmp byte [argument_str + 2], 0
    jne .not_cd_drive

    mov al, [argument_str]
    ; Перевод в верхний регистр
    cmp al, 'a'
    jb .cd_ds_upper
    cmp al, 'z'
    ja .cd_ds_upper
    sub al, 32
.cd_ds_upper:
    ; Проверяем через BIOS, существует ли такой диск
    call check_drive
    jc .invalid_drive
    
    ; Если диск существует
    mov [current_drive], al
    mov byte [current_path], 0
    jmp .done

.invalid_drive:
    mov si, msg_invalid_drive
    call print_string
    jmp .done

.not_cd_drive:
    ; Проверка на "cd \" (в корень)
    cmp byte [argument_str], '\'
    je .cd_root
    cmp byte [argument_str], '/'
    je .cd_root

    ; Проверка на "cd .." (на уровень выше)
    cmp byte [argument_str], '.'
    jne .cd_normal
    cmp byte [argument_str + 1], '.'
    jne .cd_normal
    call go_back_dir
    jmp .done

.cd_root:
    mov byte [current_path], 0
    jmp .done

.cd_normal:
    ; Просто перезаписываем текущий путь
    mov si, argument_str
    mov di, current_path
    call strcpy
    jmp .done

.done:
    ret

; =========================================================
; Проверка существования диска через BIOS INT 13h
; Вход: AL = буква диска (например, 'A')
; Выход: CF=1 если диска нет, CF=0 если есть
; =========================================================
check_drive:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    ; Переводим ASCII букву в номер BIOS (0=А, 1=B, 0x80=C)
    cmp al, 'C'
    jae .is_hdd
    sub al, 'A'
    mov dl, al
    jmp .do_check
.is_hdd:
    sub al, 'C'
    add al, 0x80
    mov dl, al

.do_check:
    mov ah, 0x08    ; Функция BIOS: получить параметры диска
    int 0x13        ; Если диска нет, BIOS установит флаг CF
    ; (флаг CF сохранится при выходе)
    
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =========================================================
; Вспомогательные процедуры для работы с путями
; =========================================================
build_prompt:
    mov si, prompt_prefix
    mov di, prompt_buffer
    call strcpy
    mov al, [current_drive]
    call append_char
    mov al, ':'
    call append_char
    mov al, '\'
    call append_char
    mov si, current_path
    call append_string
    mov si, prompt_suffix
    call append_string
    ret

build_dir_path:
    mov si, msg_dir_start
    mov di, prompt_buffer
    call strcpy
    mov al, [current_drive]
    call append_char
    mov al, ':'
    call append_char
    mov al, '\'
    call append_char
    mov si, current_path
    call append_string
    ret

go_back_dir:
    mov si, current_path
.find_end:
    lodsb
    cmp al, 0
    jne .find_end
    dec si 
    cmp si, current_path
    je .already_root
    
    dec si 
.find_slash:
    cmp byte [si], '\'
    je .found_slash
    cmp si, current_path
    je .found_slash
    dec si
    jmp .find_slash
.found_slash:
    mov byte [si], 0
    ret
.already_root:
    mov byte [current_path], 0
    ret

; =========================================================
; Процедура чтения строки
; =========================================================
read_string:
    mov di, cmd_buffer
    xor cx, cx

.wait_key:
    mov ah, 0x00
    int 0x16

    cmp al, 0x0D        ; Enter
    je .enter_pressed
    cmp al, 0x08        ; Backspace
    je .backspace

    cmp cx, 60
    jae .wait_key

    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07
    int 0x10

    mov [di], al
    inc di
    inc cx
    jmp .wait_key

.backspace:
    cmp cx, 0
    je .wait_key

    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10

    dec di
    dec cx
    jmp .wait_key

.enter_pressed:
    mov byte [di], 0
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
    ret

; =========================================================
; Строковые функции
; =========================================================
strcmp:
    push si
    push di
.loop:
    mov al, [si]
    mov bl, [di]
    
    cmp al, 'a'
    jb .check_bl
    cmp al, 'z'
    ja .check_bl
    sub al, 32
.check_bl:
    cmp bl, 'a'
    jb .compare
    cmp bl, 'z'
    ja .compare
    sub bl, 32
.compare:
    cmp al, bl
    jne .not_equal
    cmp al, 0
    je .equal
    inc si
    inc di
    jmp .loop
.not_equal:
    pop di
    pop si
    clc
    ret
.equal:
    pop di
    pop si
    stc
    ret

strcpy:
    push di
.loop:
    lodsb
    stosb
    cmp al, 0
    jne .loop
    pop di
    ret

append_char:
    stosb
    mov byte [di], 0
    ret

append_string:
    push di
.loop:
    lodsb
    stosb
    cmp al, 0
    jne .loop
    pop di
    ret

; =========================================================
; Очистка экрана
; =========================================================
clear_screen:
    mov ah, 0x06
    mov al, 0
    mov bh, 0x07
    mov cx, 0x0000
    mov dx, 0x184F
    int 0x10
    mov ah, 0x02
    mov bh, 0
    mov dx, 0x0000
    int 0x10
    ret

; =========================================================
; Вывод строки (SI = адрес строки)
; =========================================================
print_string:
    push ax
    push bx
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x0A
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

; =========================================================
; Данные
; =========================================================
cmd_buffer   times 64 db 0
command_str  times 16 db 0
argument_str times 32 db 0
current_path times 32 db 0
prompt_buffer times 64 db 0
current_drive db 'A'

cmd_help  db "HELP", 0
cmd_clear db "CLEAR", 0
cmd_dir   db "DIR", 0
cmd_cd    db "CD", 0

prompt_prefix db "OSDOS ", 0
prompt_suffix db "> ", 0
msg_dir_start db "Directory of ", 0

msg_welcome db "OSDOS 1.0 Shell", 13, 10, "Type 'help' for commands.", 13, 10, 0
msg_unknown db "Unknown command.", 13, 10, 0
msg_invalid_drive db "Invalid drive specification", 13, 10, 0

; --- ОБНОВЛЕННЫЙ HELP ---
msg_help_text db "Available commands:", 13, 10, "  help    - Show this menu", 13, 10, "  clear   - Clear the screen", 13, 10, "  dir     - List files", 13, 10, "  cd DISK - Change drive (e.g. cd A:)", 13, 10, 0

msg_dir_files db 13, 10, "KERNEL  BIN     512  01-01-2026", 13, 10, "GUI     BIN   65536  01-01-2026", 13, 10, 0

times 4096-($-$$) db 0