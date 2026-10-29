;-------------------------------------------------------------------------------
; --- BASIC STUB ---
;-------------------------------------------------------------------------------
.segment "LOADADDR"
.word $1001

.segment "BASIC"

.word nextline
.word 0
.byte $9E, "4109", 0
nextline:
.word 0

;-------------------------------------------------------------------------------
; --- VIC TURBO TERM START (MC6850 ACIA ADAPTATION) ---
;-------------------------------------------------------------------------------
.segment "CODE"
.export _start

;-------------------------------------------------------------------------------
; --- ADDRESSES ---
;-------------------------------------------------------------------------------
; MC6850 ACIA Registers (Base = $9900 / 39168)
ACIA_CTRL = $9900                   ; Write: Control Register
ACIA_STAT = $9900                   ; Read:  Status Register
ACIA_DATA = $9901                   ; Read:  Rx Data / Write: Tx Data
ACIA_BAUD = $9902                   ; Write: Baud Rate Generator (39170)

; Screen 
SC        = $900F                   ; 36879 - screen and border colour register

; KERNAL routines and vector
IRQ_VEC   = $0314                   ; IRQ vector address
GETIN     = $FFE4                   ; get a character from the keyboard buffer
CHROUT    = $FFD2                   ; output a character

;-------------------------------------------------------------------------------
; --- MAIN FUNCTION ---
;-------------------------------------------------------------------------------
_start:

    sei                             ; disable IRQs while hooking vector

    ; hook vector
    lda IRQ_VEC
    sta old_irq
    lda IRQ_VEC+1
    sta old_irq+1

    lda #<acia_irq_handler
    sta IRQ_VEC
    lda #>acia_irq_handler
    sta IRQ_VEC+1

    ; Set Baud Rate on hardware generator ($9902)
    lda #192                         ; 1200 baud (matching BASIC line 15)
    sta ACIA_BAUD

    ; Master Reset MC6850 ACIA (matching BASIC line 20)
    lda #$03                        ; Master reset bits (CR1=1, CR0=1)
    sta ACIA_CTRL

    ; Configure MC6850 ACIA Control Register (matching BASIC line 22 + Rx IRQ Enable)
    ; Bit 7   = 1 (Receive Interrupt Enable - RRIE)
    ; Bit 6-5 = 10 (RTS High, Transmit Interrupt Disabled)
    ; Bit 4-2 = 101 (8 Bits, No Parity, 1 Stop Bit)
    ; Bit 1-0 = 01 (Clock Divide Ratio /16)
    ; Total = %11010101 = $D5 (or 213 decimal)
    lda #$D5
    sta ACIA_CTRL

    cli                             ; enable IRQs

    ; black screen and border
    lda #$08
    sta SC

    ; clear screen and display READY message
    lda #<MESSAGE
    ldx #>MESSAGE
    jsr print

    jsr cursor_on

main_loop:
    ; process buffer
    sei                             ; disable IRQ while reading pointers
    lda buf_head
    cmp buf_tail
    cli                             ; re-enable IRQ
    beq check_keyboard              ; check keyboard if buffer empty

    jsr cursor_off                  ; otherwise, turn off cursor

    ; read byte from buffer
    ldx buf_tail
    lda ring_buffer,x
    inc buf_tail                    ; auto wrap at 256 bytes
    jsr CHROUT                      ; print byte

check_keyboard:
    jsr cursor_on                   ; turn cursor on
    jsr GETIN                       ; look for key
    beq main_loop                   ; jump back if no key

    cmp #$88                        ; F7 key?
    beq exit_program                ; yes -> exit

    ; otherwise send char over 6850 ACIA
    tax                             ; save char in XR
wait_tx:
    lda ACIA_STAT
    and #$02                        ; Bit 1: Tx Data Register Empty (TDRE) on MC6850
    beq wait_tx                     ; wait until ready
    stx ACIA_DATA                   ; write byte to Tx buffer

    jmp main_loop                   ; jump back for next char

exit_program:
    jsr cursor_off                  ; turn off cursor

    ; Disable 6850 Rx IRQs before unhooking vector
    lda #$55                        ; Disable Rx IRQ, RTS High, /16, 8N1
    sta ACIA_CTRL

    ; restore original IRQ vector
    lda old_irq
    sta $0314
    lda old_irq+1
    sta $0315
    cli

    rts                             ; return from subroutine (to BASIC)    

;-------------------------------------------------------------------------------
; --- IRQ HANDLER ---
;-------------------------------------------------------------------------------
acia_irq_handler:
    lda ACIA_STAT
    and #$80                        ; Bit 7: IRQ Flag on MC6850 (1 = ACIA caused IRQ)
    beq chain_irq                   ; exit if not our interrupt

    ; otherwise handle incoming Rx data
    lda ACIA_DATA                   ; read byte (clears 6850 Rx interrupt)
    ldx buf_head
    sta ring_buffer,x               ; store byte in buffer
    
    inx                             ; increment head pointer 
    cpx buf_tail                    ; compare to tail pointer
    beq irq_exit                    ; if they are equal, then buffer is full
                                    ; so we bail early and don't update head pointer
                                    ; next byte will overwrite last byte if still full

    stx buf_head                    ; otherwise update head pointer

irq_exit:
    ; ACK IRQ & exit
    pla                             ; restore AC, XR, YR saved by KERNAL entry
    tay
    pla
    tax
    pla
    rti                             ; return from interrupt

chain_irq:
    jmp (old_irq)                   ; pass execution to standard KERNAL IRQ handler

;-------------------------------------------------------------------------------
; --- PRINT ---
;-------------------------------------------------------------------------------
print:
    sta $FC                         ; store low byte in zero page
    stx $FD                         ; store high byte in zero page
    ldy #$00                        ; reset counter
next_char:
    lda ($FC), y                    ; load next char to print
    beq done                        ; if zero, then we're done
    jsr CHROUT                      ; otherwise print char
    iny                             ; increment counter
    bne next_char                   ; get next char
done:
    rts                             ; return from subroutine

;-------------------------------------------------------------------------------
; --- CURSOR ON ---
;-------------------------------------------------------------------------------
cursor_on:
        lda CURSOR                  ; check if cursor is on
        beq cursor_on_done          ; if 0, it's already on

        jsr cursor_flip             ; otherwise flip cursor byte

        lda #$00                    ; load zero into AC
        sta CURSOR                  ; update cursor (ON)

cursor_on_done:
        rts                         ; return from subroutine

;-------------------------------------------------------------------------------
; --- CURSOR OFF ---
;-------------------------------------------------------------------------------
cursor_off:

        lda CURSOR                  ; check if cursor is off
        bne cursor_off_done         ; if non-zero, already off!

        jsr cursor_flip             ; otherwise flip cursor byte

        lda #$FF                    ; update cursor (OFF)
        sta CURSOR

cursor_off_done:
        rts                         ; return from subroutine

;-------------------------------------------------------------------------------
; --- CURSOR FLIP ---
;-------------------------------------------------------------------------------
cursor_flip:
        ldy $D3                     ; column offset
        lda ($D1), y                ; read char at current pos
        eor #$80                    ; reverse the char
        sta ($D1), y                ; write it back
        rts                         ; return from subroutine

;-------------------------------------------------------------------------------
; --- DATA & BSS ---
;-------------------------------------------------------------------------------
.segment "DATA"
MESSAGE:        .byte $93,$0E,$05,"READY.",$0D,$00
CURSOR:         .byte $FF
old_irq:        .word $00
buf_head:       .byte $00
buf_tail:       .byte $00

.segment "BSS"
.align $100                         ; page align buffer for 8-bit wrap
ring_buffer:    .res $100           ; 256-byte circular buffer