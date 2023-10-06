; =====================================================
;
; Low-level disk services (BIOS int 0x13)
;
; This file is part of MetalBIOS for PK-88.
;
; =====================================================

        cpu     8086
        bits    16

        %include "disk.inc"

        section .text

; BIOS 0x13 ISR
;
; Args:
;   AH - function number
global  int13h_isr
int13h_isr:
        push    bx  ; Save BX to perform pointer arithmetic

        mov     bl, ah
        xor     bh, bh  ; BX now contains function number

        ; Load int13h_function_table with BX*2 offset into BX
        shl     bx, 1
        mov     bx, [cs:bx+int13h_function_table]

        call    bx  ; Call appropriate function

        pop     bx

        iret

int13h_function_table:
        ; https://en.wikipedia.org/wiki/INT_13H#List_of_INT_13h_services
        dw      reset_disk_system
        dw      get_status_of_last_drive_operation
        dw      read_sectors_from_drive
        dw      write_sectors_to_drive
        dw      int13h_nop
        ; TODO: Implement the rest

; No-op (unimplemented) function
int13h_nop:
        ret

; Function 00h: Reset disk system
;
; Args:
;   AH - function number (0x00)
reset_disk_system:
        ret

; Function 01h: Get status of last drive operation
;
; Args:
;   AH - function number (0x01)
;   DL - drive number (0x00 = floppy, 0x80 = hard disk)
;
; Return:
;   Carry flag set on error
;   AH - status code
get_status_of_last_drive_operation:
        ret

; Function 02h: Read sectors from drive
;
; CX =       ---CH--- ---CL---
; cylinder : 76543210 98
; sector   :            543210;
;
; cylinder = CL << 8 | CH
; sector   = CL & 0b00111111
;
;
; CX := ( ( cylinder and 255 ) shl 8 ) or ( ( cylinder and 768 ) shr 2 ) or sector;
; cylinder := ( (CX and $FF00) shr 8 ) or ( (CX and $C0) shl 2)
; sector := CX and 63;
;
; Args:
;   AH - function number (0x02)
;   AL - number of sectors to read
;   CH - cylinder number
;   CL - sector number (starting at 1)
;   DH - head number
;   DL - drive number (0x00 = floppy, 0x80 = hard disk)
;   ES:BX - pointer to buffer
;
; Return:
;  Carry flag set on error
;  AH - status code
;  AL - number of sectors read
read_sectors_from_drive:
        push    bx
        push    cx
        push    dx

        ; Calculate LBA
        ; TODO: Use DL to determine drive type?
        push    ax
        call    chs_to_lba
        pop     cx
        xor     ch, ch
        ; AX = LBA, CX = number of sectors to read

        ; TODO: Read sectors from uSD card

        pop     dx
        pop     cx
        pop     bx

        ret

; Function 03h: Write sectors to drive
;
; Args:
;   AH - function number (0x03)
;   AL - number of sectors to write
;   CH - track
;   CL - sector
;   DH - head
;   DL - drive number (0x00 = floppy, 0x80 = hard disk)
;   ES:BX - pointer to buffer
;
; Return:
;   Carry flag set on error
;   AH - status code
;   AL - number of sectors written
write_sectors_to_drive:
        push    bx
        push    cx
        push    dx

        ; Calculate LBA
        ; TODO: Use DL to determine drive type?
        push    ax
        call    chs_to_lba
        pop     cx
        xor     ch, ch
        ; AX = LBA, CX = number of sectors to write

        ; TODO: Read sectors from uSD card

        pop     dx
        pop     cx
        pop     bx

        ret

; Convert CHS to LBA while respecting the 1024 cylinder limit (upper 2 bits of CL)
; Supports disks up to 32GiB in size (65535 LBA sectors)
;
; Formula: LBA = (cylinder * HEADS + head) * SECTORS + sector - 1
;
; Args:
;   CH - cylinder number
;   CL - sector number (starting at 1)
;   DH - head number
;
; Return:
;   AX - LBA
chs_to_lba:
        push    cx

        ; AX = cylinder
        xchg    ch, cl          ; CX = 98xxxxxx 76543210
        and     ch, 0b11000000  ; CX = 98000000 76543210
        ror     ch, 1
        ror     ch, 1
        ror     ch, 1
        ror     ch, 1
        ror     ch, 1
        ror     ch, 1           ; CX = 00000098 76543210 (
        clc
        mov     ax, cx          ; AX = cylinder number

        ; AX = cylinder * HEADS
        mov     cx, DISK_HEADS
        push    dx
        mul     cx  ; clobbers DX, never overflows
        pop     dx

        ; AX = (cylinder * HEADS) + head
        xor     cx, cx
        mov     cl, dh
        add     ax, cx

        ; AX = (cylinder * HEADS + head) * SECTORS
        mov     cx, DISK_SECTORS
        push    dx
        mul     cx  ; clobbers DX, never overflows
        pop     dx

        ; AX = (cylinder * HEADS + head) * SECTORS + sector
        pop     cx
        push    cx
        and     cx, 0x003F
        dec     cl
        add     ax, cx

        pop     cx

        ret
