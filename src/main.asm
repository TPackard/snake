;     ______  __ ___  ___, ,__ ___   ______
;    /  ___/ /  \  / /   | |  /  /  /  ___/
;   /___  / / \  \/ /  / | |    <  /  ___/
;  /_____/ /__ \_/ /__/|_| |__\__\/_____/
; $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
;
;            By Tyler Packard
;
;            started 08/27/16
;           completed ??/??/??
;
section .rodata

; externs
extern add_wch
extern beep
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
extern refresh
extern setlocale
extern stdscr

global _start

; constant strings
locale: db 'en_US.UTF-8',0
urandom_path: db '/dev/urandom',0

; struct cchar_t constants for printing in ncurses
shade_l_char: dd 0, 0x2591, 0, 0, 0, 0, 0   ; light shade   '░'
shade_m_char: dd 0, 0x2592, 0, 0, 0, 0, 0   ; medium shade  '▒'
shade_d_char: dd 0, 0x2593, 0, 0, 0, 0, 0   ; dark shade    '▓'
block_char: dd 0, 0x2588, 0, 0, 0, 0, 0     ; full block    '█'
blank_char: dd 0, 0x0020, 0, 0, 0, 0, 0     ; space         ' '

; jump table for snake movement
move_table: dq _start.MT_L, _start.MT_R, _start.MT_D, _start.MT_U

; general constants
INIT_SBUF_SIZE equ 32   ; initial snake buffer size
FRAME_LEN equ 100000000 ; length of a single frame in nanoseconds

; arena size
arena_x equ 0           ; x position of arena
arena_y equ 1           ; y position of arena
arena_base  equ ((arena_y + 1) << 16) + arena_x + 1 ; position of top left corner
arena_size  equ 16      ; inside size of one side of the arena

; values corresponding to each direction
DIR_LEFT  equ 0
DIR_RIGHT equ 1
DIR_DOWN  equ 2
DIR_UP    equ 3

; keycodes
key_down  equ 0x0102    ; down arrow
key_up    equ 0x0103    ; up arrow
key_left  equ 0x0104    ; left arrow
key_right equ 0x0105    ; right arrow
key_q     equ 0x0071    ; Q

; constants for external functions (sorted alphabetically by function name)
ERR equ -1              ; general error value
CLOCK_MONOTONIC equ 1   ; clock_nanosleep - measure relative to monotonic clock
TIMER_ABSTIME equ 1     ; clock_nanosleep - sleep until absolute time
O_RDONLY equ 0          ; open - open for reading only
LC_ALL equ 6            ; setlocale - modify all of locale

; syscall numbers
SYS_OPEN  equ 0x02
SYS_CLOCK_NANOSLEEP equ 0xE6
SYS_CLOSE equ 0x03
SYS_EXIT  equ 0x3C


section .bss

; snake
snake_dir: resb 1       ; direction snake is moving
snake_len: resw 1       ; length of snake

; snake buffer (sbuf)
sbuf_base: resq 1       ; address of base of snake buffer
sbuf_size: resw 1       ; size of snake buffer
sbuf_mask: resw 1       ; mask for element indices in buffer
sbuf_off:  resw 1       ; offset of head within snake buffer

; food
food_pos: resd 1        ; position of food (y: word, x: word)

; timer
sleep_ts: resq 2        ; timespec to sleep until (absolute time)


section .text
_start:
    ; save stack
    push rbp
    push rsp

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
    jmp .no_clr_sbuf                        ; don't clear snake buffer on first initialization
.init_sbuf:
    add rsp, [sbuf_size]                    ; clear snake buffer
.no_clr_sbuf:
    mov word [sbuf_size], INIT_SBUF_SIZE    ; size of snake buffer
    sub rsp, [sbuf_size]                    ; allocate space for circular snake buffer
    mov [sbuf_base], rsp                    ; save base address of buffer

    xor rax, rax                            ; create mask for buffer indices
    mov ax, [sbuf_size]                     ;
    dec rax                                 ;
    mov [sbuf_mask], ax                     ;

    ; initialize snake
.init_snake:
    mov byte [snake_dir], DIR_DOWN      ; initialize direction down
    mov word [snake_len], 4             ; initialize snake length
    mov dword [rsp],      0x00040004    ; default snake placement
    mov dword [rsp + 4],  0x00040005    ;
    mov dword [rsp + 8],  0x00040006    ;
    mov dword [rsp + 12], 0x00040007    ;
    mov word [sbuf_off],  12            ; save offset of head withing buffer

    ; draw snake
    call clear              ; clear in case resetting after death
    xor r12, r12
    mov r12w, [sbuf_mask]   ; get snake buffer index mask
    xor rcx, rcx
    mov cx, [snake_len]     ; loop over all snake segments
    xor rbp, rbp
    mov bp, [sbuf_off]      ; get buffer head offset, use for reading snake buffer
    jmp .init_loop_start    ; skip offset decrement for first segment
.init_loop:
    ; decrement snake segment offset
    sub rbp, 4
    and rbp, r12
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

    ; draw arena
    xor rcx, rcx
    mov rcx, arena_size + 1     ; get length of walls surrounding arena
.draw_arena:
    mov rbx, rcx                ; cache rcx...
    mov rdi, rbx                ; draw top wall
    add rdi, arena_y << 16      ; add y position
    mov rsi, shade_l_char
    call draw_char
    mov rdi, rbx                ; draw bottom wall
    dec rdi                     ; calculate x position
    add rdi, (arena_size + arena_y + 1) << 16   ; add y position
    mov rsi, shade_l_char
    call draw_char
    mov rdi, rbx                ; draw left wall
    add rdi, arena_y - 1        ; calculate y position
    shl rdi, 16                 ;
    mov rsi, shade_l_char
    call draw_char
    mov rdi, rbx                ; draw right wall
    add rdi, arena_y            ; calculate y position
    shl rdi, 16                 ;
    add rdi, arena_size + 1     ; add x position
    mov rsi, shade_l_char
    call draw_char
    mov rcx, rbx                ; ...restore rcx
    loop .draw_arena

    ; save start time
    mov rdi, CLOCK_MONOTONIC
    mov rsi, sleep_ts
    call clock_gettime

; main loop:
; * sleep until next frame
; * get input
; * update snake position
; * check for collisions
; * redraw screen
.main_loop:
    call refresh

    ; calculate next time to sleep to
    mov rdx, sleep_ts
    add qword [rdx + 8], FRAME_LEN      ; increase nanosecond count
    cmp qword [rdx + 8], 1000000000     ; check for overlow in nanoseconds
    jl .sleep
    sub qword [rdx + 8], 1000000000     ; move overflow into second count
    inc qword [rdx]                     ;

    ; sleep
.sleep:
    mov rax, SYS_CLOCK_NANOSLEEP
    mov rdi, CLOCK_MONOTONIC
    mov rsi, TIMER_ABSTIME
    xor r10, r10
    syscall

    ; get input
    call getch
    cmp ax, ERR         ; error, assume no input
    je .end_input       ;

    ; parse input
    cmp rax, key_down   ; movement
    je .input_move
    cmp rax, key_up
    je .input_move
    cmp rax, key_left
    je .input_move
    cmp rax, key_right
    je .input_move
    cmp rax, key_q      ; quit
    je .exit_loop
    jmp .end_input      ; no input

.input_move:
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
    jnz .init_sbuf          ; reset game on collision

    ; make sure snake is in arena
    mov eax, edi
    cmp ax, arena_x                 ; left wall
    jle .init_sbuf
    cmp ax, arena_x + arena_size    ; right wall
    jg .init_sbuf
    shr rax, 16                     ; get y position
    cmp ax, arena_y                 ; top wall
    jle .init_sbuf
    cmp ax, arena_y + arena_size    ; bottom wall
    jg .init_sbuf

    ; save new head position
    xor rax, rax
    mov ax, [sbuf_mask]         ; get snake buffer index mask
    xor rbp, rbp
    mov bp, [sbuf_off]
    add rbp, 4
    and rbp, rax                ; get new head offset
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
    call beep               ; ate food, play beep

    ; extend snake and add new food
    inc word [snake_len]
    mov ax, [sbuf_size]
    shr ax, 2               ; get max capacity of snake buffer
    cmp ax, [snake_len]
    jg .no_extend_sbuf

    ; extend snake buffer
    mov rbp, rsp            ; save old base address
    sub sp, [sbuf_size]     ; double snake buffer size
    mov [sbuf_base], rsp    ; save new buffer base address
    shl ax, 3               ; double sbuf_size value (2 to undo shr, 1 to double)
    mov [sbuf_size], ax     ;
    dec ax                  ; extend mask for buffer indices
    mov [sbuf_mask], ax     ;

    ; shift snake segments from head to base of buffer to new base
    xor rcx, rcx
    mov cx, [sbuf_off]      ; loop from head to base address of snake buffer
.sbuf_shift_loop:
    mov eax, [rbp + rcx]    ; move data from address relative to old base address...
    mov [rsp + rcx], eax    ; ...to address relative to new base address
    sub rcx, 4
    jns .sbuf_shift_loop    ; loop on non-negative offset

.no_extend_sbuf:
    call add_food
    jmp .main_loop          ; skip erasing tail

.no_food:
    ; erase tail
    xor rbx, rbx
    mov bx, [sbuf_mask]     ; get snake buffer index mask
    xor rax, rax
    mov ax, [snake_len]
    shl rax, 2              ; get distance of tail from head in bytes
    sub rbp, rax
    and rbp, rbx            ; calculate tail offset
    mov edi, [rbp + rsp]    ; get tail position
    mov rsi, blank_char
    call draw_char

    ; bottom of .main_loop
    jmp .main_loop

.exit_loop:
    ; clean up and exit
    call endwin             ; close ncurses
    add sp, [sbuf_size]     ; reset stack
    pop rsp                 ;
    pop rbp                 ;

    ; exit with code 0
    mov rax, SYS_EXIT
    xor rdi, rdi
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
    add rax, arena_base     ; offset to fit within arena

    ; regenerate if inside snake
    mov edi, eax
    call in_snake            ; check if new position is in snakee
    test rax, rax
    jnz .gen_location       ; regenerate if inside

    mov [food_pos], edi     ; save location

    ; draw food
    mov rsi, shade_m_char
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
    xor rax, rax
    mov ax, [sbuf_mask]     ; get snake buffer index mask
    mov rbx, [sbuf_base]    ; get snake buffer base address
    xor rcx, rcx
    mov cx, [snake_len]     ; loop over all snake segments
    xor rbp, rbp
    mov bp, [sbuf_off]      ; get buffer head offset, use for reading snake buffer
    jmp .loop_start
.loop:
    ; decrement snake segment offset
    sub rbp, 4
    and rbp, rax
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
