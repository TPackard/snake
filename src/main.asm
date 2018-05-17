;     ______  __ ___  ___, ,__ ___   ______
;    /  ___/ /  \  / /   | |  /  /  /  ___/
;   /___  / / \  \/ /  / | |    <  /  ___/
;  /_____/ /__ \_/ /__/|_| |__\__\/_____/
; $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
;
;            By Tyler Packard
;
;            started 08/27/17
;             ended ??/??/??
;
section .rodata

; externs
extern add_wch
extern clear
extern clock_gettime
extern curs_set
extern endwin
extern getch
extern initscr
extern keypad
extern mvadd_wch
extern nodelay
extern noecho
extern setlocale
extern stdscr

global _start

; constant strings
locale: db 'en_US.UTF-8',0
urandom_path: db '/dev/urandom',0

; struct cchar_t constants for printing in ncurses
block_char: dd 0, 0x2588, 0, 0, 0, 0, 0     ; equals '█'
shade_char: dd 0, 0x2592, 0, 0, 0, 0, 0     ; equals '▒'
blank_char: dd 0, 0x0020, 0, 0, 0, 0, 0     ; equals ' '

; jump table for snake movement
move_table: dq _start.MT_L, _start.MT_R, _start.MT_D, _start.MT_U

; keycodes
key_down  equ 0x0102    ; down arrow
key_up    equ 0x0103    ; up arrow
key_left  equ 0x0104    ; left arrow
key_right equ 0x0105    ; right arrow
key_q     equ 0x0071    ; Q

; constants for external functions
CLOCK_REALTIME equ 1    ; clock_gettime, get seconds and nanoseconds since epoch
ERR equ -1              ; general error value
LC_ALL equ 6            ; setlocale, modify all of locale
O_RDONLY equ 0          ; open, open for reading only

; syscall numbers
SYS_OPEN  equ 0x02
SYS_CLOSE equ 0x03
SYS_EXIT  equ 0x3C


section .bss

; snake
snake_dir: resb 1       ; direction snake is moving
snake_len: resw 1       ; length of snake

; snake buffer (sbuf)
sbuf_base: resq 1       ; address of base of snake buffer
sbuf_size: resw 1       ; size of snake buffer
sbuf_off:  resw 1       ; offset of head within snake buffer

; food
food_pos: resd 1        ; position of food (y: word, x: word)

; timer
cur_ts: resq 2          ; current time timespec
old_ts: resq 2          ; old timespec, for finding time difference between updates


section .text
_start:
    ; initialize ncurses with standard US locale
    mov rsi, locale
    mov rdi, LC_ALL
    call setlocale
    call initscr

    ; hide cursor and do not echo input
    xor rdi, rdi        ; set cursor visibility to 0
    call curs_set
    call noecho

    ; make input non-blocking
    mov rdi, [stdscr]
    mov rsi, 1          ; bool, enable nodelay
    call nodelay

    ; get full input
    mov rdi, [stdscr]
    mov rsi, 1          ; bool, enable keypad
    call keypad

    ; create snake segment buffer
    mov word [sbuf_size], 72    ; size of snake segment buffer
    push rbp
    sub rsp, [sbuf_size]        ; allocate space for circular snake buffer
    mov [sbuf_base], rsp        ; save base address of buffer

    ; initialize snake
.init_snake:
    mov byte [snake_dir], 2             ; initialize direction down
    mov word [snake_len], 4             ; initialize snake length
    mov dword [rsp],      0x00040004    ; default snake placement
    mov dword [rsp + 4],  0x00040005    ;
    mov dword [rsp + 8],  0x00040006    ;
    mov dword [rsp + 12], 0x00040007    ;
    mov word [sbuf_off], 12             ; save offset of head withing buffer

    ; draw snake
    call clear              ; clear in case resetting after death
    xor rcx, rcx
    mov cx, [snake_len]     ; loop over all snake segments
    xor rbp, rbp
    mov bp, [sbuf_off]      ; get buffer head offset, use for reading snake buffer
    jmp .init_loop_start    ; skip offset decrement for first segment
.init_loop:
    ; decrement snake segment offset
    sub rbp, 4
    and rbp, 0x3F
.init_loop_start:
    ; print snake segment
    mov edi, [rbp + rsp]    ; get snake segment (offset + base addr)
    mov rsi, block_char
    mov rbx, rcx            ; cache rcx...
    call draw_char          ;
    mov rcx, rbx            ; ...restore rcx
    loop .init_loop

    ; initialize food
    call add_food

    ; save start time
    mov rdi, CLOCK_REALTIME
    mov rsi, old_ts
    call clock_gettime

; main loop:
; * get input
; * update snake position
; * check for collisions
; * redraw screen
.main_loop:
    ; get input
    call getch
    cmp ax, ERR         ; error, assume no input
    je .end_input       ;

    ; parse input
    cmp rax, key_down   ; movement
    je .move_snake
    cmp rax, key_up
    je .move_snake
    cmp rax, key_left
    je .move_snake
    cmp rax, key_right
    je .move_snake
    cmp rax, key_q      ; quit
    je .exit_loop
    jmp .end_input      ; no input

.move_snake:
    ; ensure new direction is perpendicular
    ; (2nd least sig. bit must be different between new and old direction)
    xor al, [snake_dir]     ; xor new and old direction
    test al, 2              ; mask 2nd least sig. bit
    jz .end_input           ; invalid direction, don't change

    ; get movement direction
    xor al, [snake_dir]     ; undo previous xor
    and al, 3               ; mask for lowest two bits
    mov [snake_dir], al     ; save direction

.end_input:
    ; get time elapsed since last update
    mov rdi, CLOCK_REALTIME
    mov rsi, cur_ts
    call clock_gettime

    mov r13, [cur_ts + 8]   ; compare nanoseconds
    cmp r13, [old_ts + 8]   ;
    jg .check_time_diff
    add r13, 1000000000     ; add 1 sec to current nanosec count if current nanosec
                            ; count is less than old, so time delta can be calculated

.check_time_diff:
    sub r13, [old_ts + 8]   ; get time delta in nanoseconds
    cmp r13, 100000000      ; check if 0.1 seconds have passed
    jl .main_loop           ; skip update if not enough time has passed

    ; save timespec
    mov rdi, 1
    mov rsi, old_ts
    call clock_gettime

    ; get head location
    xor rbp, rbp
    mov bp, [sbuf_off]
    mov edi, [rbp + rsp]    ; head offset + buffer base address

    ; move snake
    xor rcx, rcx
    mov cl, [snake_dir]
    shl rcx, 3                  ; get jump table index from snake direction
    jmp [abs move_table + rcx]  ; jump to movement update

.MT_L:                      ; move left
    dec edi
    jmp .end_move
.MT_R:                      ; move right
    inc edi
    jmp .end_move
.MT_D:                      ; move down
    add edi, 0x10000
    jmp .end_move
.MT_U:                      ; move up
    sub edi, 0x10000

.end_move:
    ; make sure snake hasn't collided with itself
    call in_snake
    test rax, rax
    jnz .init_snake         ; reset game on collision

    ; save new head position
    xor rbp, rbp
    mov bp, [sbuf_off]
    add rbp, 4
    and rbp, 0x3F               ; get new head offset
    mov word [sbuf_off], bp     ; save offset
    mov [rbp + rsp], edi        ; save new location of head

    ; draw head
    ; rdi already contains head location
    mov rsi, block_char
    call draw_char

    ; detect if food was eaten
    xor rax, rax
    mov eax, [food_pos]
    cmp eax, [rbp + rsp]    ; check if food and head location are the same
    jne .no_food            ; if not, continue to erase tail

    ; extend snake and add new food
    inc word [snake_len]
    call add_food
    jmp .main_loop          ; skip erasing tail

.no_food:
    ; erase tail
    xor rax, rax
    mov ax, [snake_len]
    shl rax, 2              ; get distance of tail from head in bytes
    sub rbp, rax
    and rbp, 0x3F           ; calculate tail offset
    mov edi, [rbp + rsp]    ; get tail position
    mov rsi, blank_char
    call draw_char

    ; bottom of .main_loop
    jmp .main_loop

.exit_loop:
    ; clean up and exit
    call endwin             ; close ncurses
    add sp, [sbuf_size]     ; reset stack
    pop rbp                 ;

    ; exit with code 0
    mov rax, SYS_EXIT
    mov rdi, 0
    syscall


; procedure - draw_char
; ---------------------
; edi - position to draw character (lower 2 bytes for x, upper 2 bytes for y).
;       upper 4 bytes must be 0
; rsi - address of cchar_t to draw
;
; Draws a character at the given position
draw_char:
    ; create stack frame, save cchar_t*
    sub rsp, 8
    mov [rsp], rsi

    ; print first char
    mov rdx, rsi        ; char
    xor rsi, rsi
    mov si, di
    shl rsi, 1          ; x pos
    shr edi, 16         ; y pos
    call mvadd_wch

    ; print second char
    mov rdi, [rsp]
    call add_wch

    ; clean up stack
    add rsp, 8
    ret


; procedure - rand_int
; --------------------
; rax - return random number between 0 and 2^64 - 1
;
; Generates a random positive integer
rand_int:
    sub rsp, 8; qword buffer to read into (will store random number)

    ; open /dev/urandom for reading
    mov rax, SYS_OPEN
    mov rdi, urandom_path
    mov rsi, O_RDONLY
    syscall

    ; read qword from /dev/urandom
    mov rdi, rax        ; /dev/urandom fd
    xor rax, rax        ; sys_read syscall number
    lea rsi, [rsp]      ; address of buffer to read into
    mov rdx, 8
    syscall

    ; close /dev/urandom fd
    mov rax, SYS_CLOSE
    syscall

    ; return random number
    mov rax, [rsp]
    add rsp, 8
    ret


; procedure - add_food
; --------------------
; Places the food at a random location and draws it
add_food:
    sub rsp, 8

    ; generate location
.gen_location:
    call rand_int           ; generate random new food position
    and rax, 0x000F000F     ; mask position to fit within arena

    ; regenerate if inside snake
    mov edi, eax
    call in_snake            ; check if new position is in snakee
    test rax, rax
    jnz .gen_location       ; regenerate if inside

    mov [food_pos], edi     ; save location

    ; draw food
    mov rsi, shade_char
    call draw_char

    add rsp, 8
    ret


; procedure - in_snake
; --------------------
; rdi - position to check
;
; rax - return 1 if inside snake, 0 otherwise
;
; Determines whether or not a given position is inside the snake
in_snake:
    mov rbx, [sbuf_base]    ; get snake buffer base address
    xor rcx, rcx
    mov cx, [snake_len]     ; loop over all snake segments
    xor rbp, rbp
    mov bp, [sbuf_off]      ; get buffer head offset, use for reading snake buffer
    jmp .loop_start
.loop:
    ; decrement snake segment offset
    sub rbp, 4
    and rbp, 0x3F
.loop_start:
    ; check if position is same as snake segment
    cmp edi, [rbp + rbx]
    je .inside              ; same position, return 1
    loop .loop

    ; return 0
    xor rax, rax
    ret

.inside:
    ; return 1
    mov rax, 1
    ret
