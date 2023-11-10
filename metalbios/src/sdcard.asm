; =====================================================
;
; SD card functions (via 16550)
; https://media.digikey.com/pdf/Data%20Sheets/Texas%20Instruments%20PDFs/PC16550D.pdf
;
; This file is part of MetalBIOS for PK-88.
;
; =====================================================


        cpu     8086
        bits    16

        %include "ports.inc"

SDC_HEADER      equ     0b01000000

        section .text

; ==================================================
; SD card functions
; ==================================================

; --------------------------------------------------
; Initialize SD card
; --------------------------------------------------
; Return:
;   AX - error code, 0 if success
        global  sdc_init
sdc_init:
        ; Init lines
        push    cx

        mov     al, 0b00000000
        out     UA_MCR, al
        mov     al, 0b11111111
        out     UA_MCR, al
        mov     al, 0b00000000
        out     UA_MCR, al
        mov     al, 0b11111111
        out     UA_MCR, al

        mov     al, 0b00001101  ; MOSI=0, /CS=1, SCK=0
        out     UA_MCR, al

        ; Reset SD card
        mov     al, 0b00000001  ; MOSI=1, /CS=1, SCK=0
        out     UA_MCR, al
        mov     cx, 80  ; Sent 80 clock pulses
.loop:
        and     al, 0b11111110  ; SCK = 1
        out     UA_MCR, al
        or      al, 0b00000001  ; SCK = 0
        out     UA_MCR, al
        loop    .loop

        call    enable

        ; CMD0 - init
        call    cmd0_go_idle_state
        call    wait_byte
        cmp     ah, 1
        jne     .go_idle_state_fail

        ; CMD8 - send voltage check
        call    cmd8_send_if_cond
        call    wait_byte       ; Read header
        mov     cx, 5           ; Skip 5 bytes
        call    skip
        cmp     ah, 1
        jne     .if_cond_fail

        ; CMD58 - read OCR
        call    cmd58_read_ocr
        call    wait_byte       ; Read header
        mov     cx, 5           ; Skip 5 bytes
        call    skip
        cmp     ah, 1
        jne     .read_ocr_fail

        ; CMD55 - send app cmd
        call    cmd55_app_cmd
        call    wait_byte       ; Read header
        mov     cx, 1           ; Skip tail
        call    skip
        cmp     ah, 1
        jne     .app_fail

        ; CMD41 - send app op cond
        call    cmd41_send_op_cond
        call    wait_byte       ; Read header
        mov     cx, 1           ; Skip tail
        call    skip
        cmp     ah, 1
        jne     .op_cond_fail

        ; CMD55 - send app cmd
        mov     cx, 0x100
.app_init:
        push    cx
        call    cmd55_app_cmd
        call    wait_byte       ; Read header
        mov     cx, 1           ; Skip tail
        call    skip

        ; CMD41 - send app op cond
        call    cmd41_send_op_cond
        call    wait_byte       ; Read header
        mov     cx, 1           ; Skip tail
        call    skip
        pop     cx
        cmp     ah, 0
        je      .app_init_ok
        loop    .app_init

        jmp     .app_init_fail
.app_init_ok:

        ; CMD55 - send app cmd
        call    cmd58_read_ocr
        call    wait_byte       ; Read header
        mov     cx, 5           ; Skip tail
        call    skip
        ; Bit 30 of OCR should now contain 1 (the card is a high-capacity card known as SDHC/SDXC)

        ; CMD16 - set block length
        mov     ax, 512
        call    cmd16_set_blocklen
        call    wait_byte       ; Read header
        mov     cx, 1           ; Skip tail
        call    skip
        cmp     ah, 0
        jne     .set_blocklen_fail

        xor     ax, ax
        jmp     .end

.go_idle_state_fail:
        mov     ax, 1
        jmp     .end
.if_cond_fail:
        mov     ax, 2
        jmp     .end
.read_ocr_fail:
        mov     ax, 3
        jmp     .end
.app_fail:
        mov     ax, 4
        jmp     .end
.op_cond_fail:
        mov     ax, 5
        jmp     .end
.app_init_fail:
        mov     ax, 6
        jmp     .end
.set_blocklen_fail:
        mov     ax, 7

.end:
        call    disable

        pop     cx
        ret

cmd0_go_idle_state:
        push    ax

        mov     al, 0 | SDC_HEADER
        call    xfer
        mov     al, 0  ; arguments
        call    xfer
        call    xfer
        call    xfer
        call    xfer
        mov     al, 0x95  ; CRC and stop bit
        call    xfer

        pop     ax
        ret

cmd8_send_if_cond:
        push    ax

        mov     al, 8 | SDC_HEADER
        call    xfer
        mov     al, 0  ; arguments
        call    xfer
        call    xfer
        mov     al, 1
        call    xfer
        mov     al, 0xaa
        call    xfer
        mov     al, 0x87  ; CRC and stop bit
        call    xfer

        pop     ax
        ret

cmd58_read_ocr:
        push    ax

        mov     al, 58 | SDC_HEADER
        call    xfer
        mov     al, 0  ; arguments
        call    xfer
        call    xfer
        call    xfer
        call    xfer
        mov     al, 0b01110101  ; CRC and stop bit
        call    xfer

        pop     ax
        ret

cmd55_app_cmd:
        push    ax

        mov     al, 55 | SDC_HEADER
        call    xfer
        mov     al, 0  ; arguments
        call    xfer
        call    xfer
        call    xfer
        call    xfer
        mov     al, 0x55  ; CRC and stop bit
        call    xfer

        pop     ax
        ret

cmd41_send_op_cond:
        push    ax

        mov     al, 41 | SDC_HEADER
        call    xfer
        mov     al, 0b01000000  ; arguments
        call    xfer
        mov     al, 0
        call    xfer
        call    xfer
        call    xfer
        mov     al, 0x77  ; CRC and stop bit
        call    xfer

        pop     ax
        ret

cmd16_set_blocklen:
        push    ax
        push    bx

        mov     bx, ax
        mov     al, 16 | SDC_HEADER
        call    xfer
        mov     al, 0  ; arguments
        call    xfer
        call    xfer
        mov     al, bh
        call    xfer
        mov     al, bl
        call    xfer
        mov     al, 0x81  ; CRC and stop bit
        call    xfer

        pop     bx
        pop     ax
        ret


; ==================================================
; SPI functions
;
; /CTS  - /MISO (MSR bit 4)
; /OUT1 - /MOSI (MCR bit 2)
; /DTR  - /SCK  (MCR bit 0)
; /RTS  -  CS   (MCR bit 1)
;
; TODO: Pull-up for MISO? (http://elm-chan.org/docs/mmc/mmc_e.html#spimode)
; ==================================================

; --------------------------------------------------
; Wait for byte from SD card
; --------------------------------------------------
; Return:
;   AH - received byte or 0xff if timeout (MISO stayed high)
wait_byte:
        push    cx

        mov     cx, 0x100
.again:
        call    xfer
        cmp     ah, 0xff
        jne     .end
        loop    .again
.end:
        pop     cx
        ret

; --------------------------------------------------
; Enable device
; --------------------------------------------------
enable:
        push    ax

        in      al, UA_MCR
        or      al, 0b00000010  ; Enable
        out     UA_MCR, al

        pop     ax
        ret

; --------------------------------------------------
; Disable device
; --------------------------------------------------
disable:
        push    ax

        in      al, UA_MCR
        and     al, 0b11111101  ; Disable
        out     UA_MCR, al

        pop     ax
        ret

; --------------------------------------------------
; Write/read byte to/from SPI
; --------------------------------------------------
; Args:
;   AL - byte written to SPI
; Return:
;   AH - byte read from SPI
        global  sdc_xfer
xfer:
        push    bx
        push    cx

        mov     cx, 8
        mov     bl, al
        mov     bh, al
        mov     al, 0b00001111  ; 7..3 = 0, 2 = MOSI, 1 = /CS, 0 = SCK
        mov     ah, 0
.next:
        rol     bl, 1
        jc      .set1
.set0:
        or      al, 0b00000100  ; MOSI = 0
        jmp     .setok
.set1:
        and     al, 0b11111011  ; MOSI = 1
.setok:
        out     UA_MCR, al      ; Write MOSI
        and     al, 0b11111110  ; SCK = 1
        out     UA_MCR, al      ; Write SCK
        ; Read start
        ; TODO: add delay?
        push    ax
        in      al, UA_MSR      ; Read MISO
        and     al, 0b00010000  ; MISO
        jz      .got1           ; MISO = 1 (/CTS = 0)
.got0:
        clc
        jmp     .gotok
.got1:
        stc
.gotok:
        pop     ax
        rcl     ah, 1
        ; Read end
        or      al, 0b00000001  ; SCK = 0
        out     UA_MCR, al      ; Write SCK

        loop    .next

        mov     al, bh          ; Restore written byte

        pop     cx
        pop     bx
        ret

; --------------------------------------------------
; Read & discard N bytes
; --------------------------------------------------
; Args:
;   CX - number of bytes to discard
skip:
        push    ax
        push    cx
.skip:
        call    xfer
        loop    .skip
        pop     cx
        pop     ax
        ret
