        .export _start
        .segment "CODE"

; -------------------------------------------------------
; ACIA addresses
; -------------------------------------------------------
ACIA_BASE   = $9900
ACIA_STATUS = ACIA_BASE + 0
ACIA_DATA   = ACIA_BASE + 1
ACIA_BAUD   = ACIA_BASE + 2

; KERNAL routines
GETIN       = $FFE4
CHROUT      = $FFD2

; -------------------------------------------------------
; MAIN ENTRY POINT (called by SYS 4109)
; -------------------------------------------------------
_start:
        ; --- init ACIA ---
        lda #12          ; 1200 baud
        sta ACIA_BAUD

        lda #3           ; reset
        sta ACIA_STATUS

        lda #85          ; /16, 8N1, RTS high, IRQ off
        sta ACIA_STATUS

        ; optional greeting
        lda #<MESSAGE
        ldx #>MESSAGE
        jsr print

main_loop:
        jsr poll_keyboard
        jsr poll_receive
        jmp main_loop

; -------------------------------------------------------
; POLL KEYBOARD (non-blocking)
; -------------------------------------------------------
poll_keyboard:
        jsr GETIN        ; A = key or 0
        beq pk_done

        ; check TX ready
        lda ACIA_STATUS
        and #$02
        beq pk_done      ; not ready

        ; send key
        jsr GETIN        ; get key again
        sta ACIA_DATA

pk_done:
        rts

; -------------------------------------------------------
; POLL RECEIVE (non-blocking)
; -------------------------------------------------------
poll_receive:
        lda ACIA_STATUS
        and #$01
        beq pr_done

        lda ACIA_DATA
        jsr CHROUT

pr_done:
        rts

; -------------------------------------------------------
; PRINT ROUTINE (you already had this)
; -------------------------------------------------------
print:
        sta $FC
        stx $FD
        ldy #0
next_char:
        lda ($FC),y
        beq done
        jsr CHROUT
        iny
        bne next_char
done:
        rts

; -------------------------------------------------------
; DATA
; -------------------------------------------------------
MESSAGE:
        .byte "HST Ready.",13,0
