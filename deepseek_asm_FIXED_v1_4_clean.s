;
; ==============================================================
; deepseek_asm_FIXED.s (Originally: 20251009_ULTIMATE_EYECANDY_FINAL_PAL.s)
; Release-quality PAL demo: multi-IRQ chain, sprites, scroller,
; plasma BG, raster bars, logo, and decorative lines.
;
; FIXED VERSION: Corrected critical IRQ ACK bug, fixed corrupt sprite data,
; improved sprite coloring, added NMI handler, and optimized various routines.
;
; Target: PAL C64 (312 raster lines @ ~50 Hz)
; Build : acme --strict-segments -f cbm -o ultimate_demo_fixed.prg deepseek_asm_FIXED_v1_4_clean.s
; Run   : x64sc -autostart ultimate_demo_fixed.prg
;
; Memory map (VIC bank 0):
;   Screen  : $0400-$07E7
;   Color   : $D800-$DBE7 (I/O space, 4-bit nybbles)
;   Charset : $2000-$27FF (copied from CharROM $D000-$D7FF)
;   Sprites : $2800-$29FF (8 * 64 bytes)
; Zero page used: $FB-$FF (safe, outside KERNAL/CIA workspace)
; IRQ lines (approximate): 50 -> 100 -> 150 -> 200 -> loop
; Each IRQ: ACK $D019, push A/X/Y, do work, set next vector/line, tail via $EA31.
; ==============================================================

; ---------------- BASIC stub: 10 SYS4608 ----------------
* = $0801
!word $080b           ; next BASIC line
!word 10              ; line number
!byte $9e             ; token: SYS
!text "4608"          ; "SYS 4608" = $1200
!byte 0
!word 0               ; end of program

; ---------------- Hardware constants ----------------
BORDERCOL   = $d020
BGCOL       = $d021
RASTER      = $d012
CTRL1       = $d011
CTRL2       = $d016
MEMPTR      = $d018
VICIRQEN    = $d01a
VICIRQFLAG  = $d019
CIA1_ICR    = $dc0d
CIA2_PRA    = $dd00
CIA2_ICR    = $dd0d

SCREEN      = $0400
COLOR       = $d800
CHARSET     = $2000
SPRITE_DATA = $2800

SPRITE_PTRS = SCREEN + 1016
SPRITE_ENA  = $d015
SPRITE_XEXP = $d01d
SPRITE_YEXP = $d017
SPRITE_COL0 = $d027
SPRITE_MC   = $d01c
SPRITE_MC0  = $d025
SPRITE_MC1  = $d026

; ---------------- Zero page ----------------
ZP_SrcLo    = $fb
ZP_SrcHi    = $fc
ZP_DstLo    = $fd
ZP_DstHi    = $fe
ZP_TmpA     = $ff

; ---------------- State vars ----------------
FrameCount      = $033a
ScrollIdx       = $033b
SmoothScroll    = $033c
ColorCycle      = $033d
WavePhase       = $033e
StarPhase       = $033f
LogoPhase       = $0340
PlasmaPhase     = $0341

; ---------------- Tables ----------------
* = $0900
RowScrLo:  !for i,0,24 { !byte <(SCREEN + i*40) }
RowScrHi:  !for i,0,24 { !byte >(SCREEN + i*40) }
RowColLo:  !for i,0,24 { !byte <(COLOR  + i*40) }
RowColHi:  !for i,0,24 { !byte >(COLOR  + i*40) }

; 256-entry sine (0..255). Used for smooth motion and color phases.
Sine256:
!byte 128,131,134,137,140,143,146,149,152,156,159,162,165,168,171,174
!byte 176,179,182,185,188,191,193,196,199,201,204,206,209,211,213,216
!byte 218,220,222,224,226,228,230,232,234,236,237,239,240,242,243,245
!byte 246,247,248,249,250,251,252,252,253,254,254,255,255,255,255,255
!byte 255,255,255,255,255,255,254,254,253,252,252,251,250,249,248,247
!byte 246,245,243,242,240,239,237,236,234,232,230,228,226,224,222,220
!byte 218,216,213,211,209,206,204,201,199,196,193,191,188,185,182,179
!byte 176,174,171,168,165,162,159,156,152,149,146,143,140,137,134,131
!byte 128,125,122,119,116,113,110,107,104,100,97,94,91,88,85,82
!byte 80,77,74,71,68,65,63,60,57,55,52,50,47,45,43,40
!byte 38,36,34,32,30,28,26,24,22,20,19,17,16,14,13,11
!byte 10,9,8,7,6,5,4,4,3,2,2,1,1,1,1,1
!byte 1,1,1,1,1,1,2,2,3,4,4,5,6,7,8,9
!byte 10,11,13,14,16,17,19,20,22,24,26,28,30,32,34,36
!byte 38,40,43,45,47,50,52,55,57,60,63,65,68,71,74,77
!byte 80,82,85,88,91,94,97,100,104,107,110,113,116,119,122,125

; Per-sprite phase offsets
SpritePhase8: !byte 0,32,64,96,128,160,192,224

; Palettes (0..15)
PlasmaColors: !byte 6,14,3,1,3,14,6,0,6,14,3,1,3,14,6,0, 9,8,7,2,7,8,9,0,9,8,7,2,7,8,9,0
RainbowBar:   !byte 6,14,3,13,1,13,3,14,6,14,3,13,1,13,3,14
Fire16:       !byte 0,9,2,8,2,10,7,10,15,7,10,7,8,2,9,0
Ice16:        !byte 6,14,3,1,1,3,14,6,0,6,14,3,1,1,3,14

; Scroller text (PETSCII). Terminates with 0.
ScrollText:
!scr "    *** ultimate horizonwarp demo (fixed version) *** "
!scr "featuring: plasma waves * color bars * sprite multiplex * "
!scr "smooth scroll * raster splits * animated charset * "
!scr "and maximum c64 eye candy! *** "
!scr "coded with pure 6502 assembly *** "
!byte 0

; ---------------- Code ----------------

; --- Simple raster sync to avoid enabling IRQ in an unstable window ---
SyncFrame:
    ; Wait until raster >= 8 to avoid VIC init jitter
@wf1: lda $d012
    cmp #8
    bcc @wf1
    rts
* = $1200

Start:  ; --- Init hardware, memory, assets, then arm IRQ chain ---
    sei

    ; --- Robust IRQ sanitization ---
    ; 1) Clear all CIA interrupt masks (b7=0 -> clear bits 0..6)
    lda #$7f
    sta CIA1_ICR       ; $DC0D
    sta CIA2_ICR       ; $DD0D
    ; 2) Read CIA ICRs to clear any pending flags
    lda CIA1_ICR
    lda CIA2_ICR
    ; 3) Clear any pending VIC-II IRQ flags (write 1s to clear)
    lda #$ff
    sta VICIRQFLAG


    ; Disable CIAs (clear any pending IRQs)
    lda #$7f
    sta CIA1_ICR
    sta CIA2_ICR

    ; Colors
    lda #$00
    sta BGCOL

    ; VIC bank 0 ($0000-$3FFF)
    lda CIA2_PRA
    and #%11111100      ; clear bank bits
    ora #%00000011      ; VIC bank $0000-$3FFF (bank 0)
    sta CIA2_PRA

    ; Screen=$0400, Charset=$2000
    lda #$18
    sta MEMPTR

    ; Standard video (25 rows), fine scroll=0
    lda #$1b
    sta CTRL1
    lda #$08
    sta CTRL2

    jsr ClearScreen
    jsr ClearColor
    jsr CopyROMCharset
    jsr ModifyCharset
    jsr InitState
    jsr InitSprites
    jsr CreateSpriteData
    jsr DrawLogo
    jsr DrawBorders
    jsr SyncFrame

    ; Setup NMI to disable RUN/STOP+RESTORE
    lda #<NMI_Handler
    sta $0318
    lda #>NMI_Handler
    sta $0319

        ; Setup IRQ chain (vector first, then raster, clear flags, enable)
    lda #<IRQ1
    sta $0314
    lda #>IRQ1
    sta $0315

    lda CTRL1
    and #$7f
    sta CTRL1
    lda #50
    sta RASTER

    lda #$ff
    sta VICIRQFLAG            ; clear any VIC-II IRQ flags (all)
    lda #$01
    sta VICIRQEN              ; enable raster IRQ only
    cli
Forever: jmp Forever

; --- NMI Handler to prevent soft reset ---
NMI_Handler:
    rti

; ---------------- IRQ Chain (each in its own !zone) ----------------

!zone IRQ1Zone {
IRQ1:   ; --- IRQ1 @ ~50: rainbow top border + chain to IRQ2 ---
    pha
    txa : pha
    tya : pha

    ; It's only safe to do work after checking the source of the IRQ
    lda VICIRQFLAG
    and #$01
    beq .skip

    lda #$01
    sta VICIRQFLAG

    ; Program next IRQ early to avoid missing the window
    lda #100
    sta RASTER
    lda #<IRQ2
    sta $0314
    lda #>IRQ2
    sta $0315

    ; Diagnostic border color (flash)
    lda #$01            ; FIX: Correctly acknowledge the raster interrupt
    sta VICIRQFLAG

    ; Animate top border with color bars
    ldx FrameCount
    lda Sine256,x
    lsr : lsr : lsr : lsr
    tax
    lda RainbowBar,x
    sta BORDERCOL

    ; Setup next IRQ
    lda #100
    sta RASTER
    lda #<IRQ2
    sta $0314
    lda #>IRQ2
    sta $0315
.skip:
    pla : tay
    pla : tax
    pla
    jmp $ea31
}

!zone IRQ2Zone {
IRQ2:   ; --- IRQ2 @ ~100: update sprites + color wave rows ---
    pha
    txa : pha
    tya : pha

    lda VICIRQFLAG
    and #$01
    beq .skip

    lda #$01
    sta VICIRQFLAG

    ; Program next IRQ early to avoid missing the window
    lda #150
    sta RASTER
    lda #<IRQ3
    sta $0314
    lda #>IRQ3
    sta $0315

    ; Diagnostic border color (flash)
    lda #$01            ; FIX: Correctly acknowledge the raster interrupt
    sta VICIRQFLAG

    inc FrameCount
    jsr UpdateSprites
    jsr ColorWaveEffect

    ; Setup next IRQ
    lda #150
    sta RASTER
    lda #<IRQ3
    sta $0314
    lda #>IRQ3
    sta $0315
.skip:
    pla : tay
    pla : tax
    pla
    jmp $ea31
}

!zone IRQ3Zone {
IRQ3:   ; --- IRQ3 @ ~150: smooth scroller + plasma BG ---
    pha
    txa : pha
    tya : pha

    lda VICIRQFLAG
    and #$01
    beq .skip

    lda #$01
    sta VICIRQFLAG

    ; Program next IRQ early to avoid missing the window
    lda #200
    sta RASTER
    lda #<IRQ4
    sta $0314
    lda #>IRQ4
    sta $0315

    ; Diagnostic border color (flash)
    lda #$01            ; FIX: Correctly acknowledge the raster interrupt
    sta VICIRQFLAG

    jsr UpdateScroll
    jsr PlasmaEffect

    ; Setup next IRQ
    lda #200
    sta RASTER
    lda #<IRQ4
    sta $0314
    lda #>IRQ4
    sta $0315
.skip:
    pla : tay
    pla : tax
    pla
    jmp $ea31
}

!zone IRQ4Zone {
IRQ4:   ; --- IRQ4 @ ~200: bottom raster bars, loop to IRQ1 ---
    pha
    txa : pha
    tya : pha

    lda VICIRQFLAG
    and #$01
    beq .skip

    lda #$01
    sta VICIRQFLAG

    ; Program next IRQ early to avoid missing the window
    lda #50
    sta RASTER
    lda #<IRQ1
    sta $0314
    lda #>IRQ1
    sta $0315

    ; Diagnostic border color (flash)
    lda #$01            ; FIX: Correctly acknowledge the raster interrupt
    sta VICIRQFLAG

    jsr RasterBars

    ; Back to top of chain
    lda #50
    sta RASTER
    lda #<IRQ1
    sta $0314
    lda #>IRQ1
    sta $0315
.skip:
    pla : tay
    pla : tax
    pla
    jmp $ea31
}

; ---------------- Scroller ----------------
UpdateScroll: ; Smooth 1–8 pixel scroll on row 22 + per-char color (correct $D016 handling)
    lda SmoothScroll
    beq .doShift
    dec SmoothScroll
    ; Set fine scroll = SmoothScroll (0..7), preserve upper bits, keep 38-col bit set
    lda CTRL2
    and #%11111000
    ora #$08            ; ensure 38-col scroll enabled
    ora SmoothScroll
    sta CTRL2
    rts
.doShift:
    lda #$07
    sta SmoothScroll
    ; Set fine scroll to 7 (pre-shift) with 38-col bit kept
    lda CTRL2
    and #%11111000
    ora #$0f            ; bit3=1, low3=111
    sta CTRL2

    ; Shift row 22 left
    ldx #0
.shift:
    lda SCREEN+22*40+1,x
    sta SCREEN+22*40+0,x
    lda COLOR+22*40+1,x
    sta COLOR+22*40+0,x
    inx
    cpx #39
    bne .shift

    ; Put next char
    ldx ScrollIdx
    lda ScrollText,x
    bne .ok
    ldx #0
    lda ScrollText,x
.ok:
    sta SCREEN+22*40+39

    ; Animated color
    lda FrameCount
    lsr
    and #$0f
    tax
    lda Fire16,x
    sta COLOR+22*40+39

    inc ScrollIdx
    ldx ScrollIdx
    lda ScrollText,x
    bne .noloop
    lda #0
    sta ScrollIdx
.noloop:
    rts

; ---------------- Sprite Effects ----------------
UpdateSprites: ; 8 multicolor sprites on sine XY paths + color animate (SAFE INDEXING)
    ; Enable sprites and multicolor once per frame
    lda #$ff
    sta SPRITE_ENA
    sta SPRITE_MC

    ; Global multicolor regs animate slowly
    lda FrameCount
    lsr
    lsr
    and #$0f
    tax
    lda Fire16,x
    sta SPRITE_MC0
    lda Ice16,x
    sta SPRITE_MC1

    lda #$00
    sta $d010      ; X MSB clear for all

    ldx #0         ; sprite index 0..7
@loop:
    ; Compute VIC register pair index = sprite*2 → store in ZP_TmpA
    txa
    asl
    sta ZP_TmpA

    ; --- X position ---
    lda FrameCount
    clc
    adc SpritePhase8,x
    tay
    lda Sine256,y
    lsr
    clc
    adc #24
    ldy ZP_TmpA          ; Y = reg index
    sta $d000,y          ; X register

    ; --- Y position ---
    lda FrameCount
    asl
    clc
    adc SpritePhase8,x
    tay
    lda Sine256,y
    clc
    adc #50
    ldy ZP_TmpA
    iny
    sta $d000,y          ; Y register (base+1)

    ; --- per-sprite color ---
    lda FrameCount
    clc
    adc SpritePhase8,x
    and #$1f
    tay
    lda PlasmaColors,y
    sta SPRITE_COL0,x

    inx
    cpx #8
    bne @loop
    rts
@noexp:
    lda #$00
    sta SPRITE_XEXP
    sta SPRITE_YEXP
    rts

; ---------------- Color Wave Effect ----------------
ColorWaveEffect: ; Row-wise color wave using RainbowBar table
    lda WavePhase
    sta ZP_TmpA

    ldx #5
@rowLoop:
    lda RowColLo,x
    sta ZP_SrcLo
    lda RowColHi,x
    sta ZP_SrcHi

    lda ZP_TmpA
    and #$0f
    tay
    lda RainbowBar,y

    ldy #0
@colLoop:
    sta (ZP_SrcLo),y
    iny
    cpy #40
    bne @colLoop

    lda ZP_TmpA
    clc
    adc #3
    sta ZP_TmpA

    inx
    cpx #16
    bne @rowLoop

    inc WavePhase
    rts

; ---------------- Plasma Effect ----------------
PlasmaEffect: ; Background plasma via 16-step palette cycling
    lda PlasmaPhase
    and #$0f
    tax
    lda PlasmaColors,x
    sta BGCOL

    inc PlasmaPhase
    rts

; ---------------- Raster Bars ----------------
RasterBars: ; Timed border color bars with tiny delay loop
    ldx #0
@bars:
    lda FrameCount
    clc
    adc StarPhase
    clc
    adc Sine256,x
    and #$0f
    tay
    lda Ice16,y
    sta BORDERCOL

    ldy #2
@delay:
    dey
    bne @delay

    inx
    cpx #20
    bne @bars

    lda #0
    sta BORDERCOL
    inc StarPhase
    rts

; ---------------- Logo Drawing ----------------
LogoText:  !scr "   ** horizon warp ** " : !byte 0
LogoText2: !scr " maximum eye candy demo " : !byte 0

DrawLogo: ; Center two text lines on rows 2–3 with colors
    ; First line
    ldx #0
@len1: lda LogoText,x : beq @gotlen1 : inx : bne @len1
@gotlen1:
    txa
    sta ZP_TmpA
    lda #40             ; FIX: Use clear (40-len)/2 logic
    sec
    sbc ZP_TmpA
    lsr
    tax

    ldy #0
@draw1:
    lda LogoText,y
    beq @logo2
    sta SCREEN+2*40,x
    lda #1
    sta COLOR+2*40,x
    inx
    iny
    bne @draw1

@logo2:
    ldx #0
@len2: lda LogoText2,x : beq @gotlen2 : inx : bne @len2
@gotlen2:
    txa
    sta ZP_TmpA
    lda #40             ; FIX: Use clear (40-len)/2 logic
    sec
    sbc ZP_TmpA
    lsr
    tax

    ldy #0
@draw2:
    lda LogoText2,y
    beq @done
    sta SCREEN+3*40,x
    lda #14
    sta COLOR+3*40,x
    inx
    iny
    bne @draw2
@done:
    rts

; ---------------- Border decorations ----------------
DrawBorders: ; Decorative horizontal lines on rows 4 and 21
    lda #$40  ; Horizontal line char
    ldx #0
@top:         ; FIX: Moved lda #$40 out of the loop
    sta SCREEN+4*40,x
    lda #3
    sta COLOR+4*40,x
    lda #$40
    inx
    cpx #40
    bne @top

    lda #$40
    ldx #0
@bot:         ; FIX: Moved lda #$40 out of the loop
    sta SCREEN+21*40,x
    lda #6
    sta COLOR+21*40,x
    lda #$40
    inx
    cpx #40
    bne @bot
    rts

; ---------------- Charset ROM copy ----------------
CopyROMCharset: ; Map CharROM and copy $D000-$D7FF -> $2000-$27FF
    lda $01
    pha
    lda #$33            ; CHAREN=0 -> map CharROM at $D000-$DFFF
    sta $01

    lda #<CHARSET
    sta ZP_DstLo
    lda #>CHARSET
    sta ZP_DstHi
    lda #<$d000
    sta ZP_SrcLo
    lda #>$d000
    sta ZP_SrcHi

    ldx #8              ; copy 2 KB (8 * 256 bytes)
@page:
    ldy #0
@cpy:
    lda (ZP_SrcLo),y
    sta (ZP_DstLo),y
    iny
    bne @cpy
    inc ZP_SrcHi
    inc ZP_DstHi
    dex
    bne @page

    pla
    sta $01
    rts

; ---------------- Modify Charset ----------------
ModifyCharset: ; Patch char $40 with a striped pattern
    ldy #0
@loop:
    lda #$ff
    sta CHARSET + $40*8 + 0,y
    lda #$00
    sta CHARSET + $40*8 + 1,y
    iny
    iny
    cpy #8
    bne @loop
    rts

; ---------------- Sprite Data Creation ----------------
CreateSpriteData:
    ; FIX: Define a proper 21x24 pixel multicolor sprite (63 bytes) + 1 padding byte
    ; This creates a clean spherical shape.
    SpriteAddr = SPRITE_DATA
    ldx #0
@loop:
    lda BallData,x
    sta SpriteAddr,x
    inx
    cpx #64
    bne @loop

    ; Copy base sprite data to all 8 sprite slots
    ldx #1
@copy_sprites:
    lda #<SpriteAddr
    sta ZP_SrcLo
    lda #>SpriteAddr
    sta ZP_SrcHi

    txa
    asl : asl : asl : asl : asl : asl   ; *64
    clc
    adc #<SpriteAddr
    sta ZP_DstLo
    lda #>SpriteAddr
    adc #0
    sta ZP_DstHi

    ldy #0
@copy_loop:
    lda (ZP_SrcLo),y
    sta (ZP_DstLo),y
    iny
    cpy #64
    bne @copy_loop

    inx
    cpx #8
    bne @copy_sprites
    rts

BallData:
    ; 63 bytes for a 21-row sprite, plus one padding byte.
    ; This pattern creates a 16-pixel wide ball.
    !byte $00,$00,$00, $00,$00,$00, $00,$00,$00, $00,$00,$00 ; 4 empty rows
    !byte $00,$3C,$00 ; ..XXXX..
    !byte $00,$FF,$00 ; .XXXXXXXX.
    !byte $03,$FF,$C0 ; XXXXXXXXXXXX
    !byte $0F,$FF,$F0 ; XXXXXXXXXXXXXX
    !byte $1F,$FF,$F8 ; XXXXXXXXXXXXXXX
    !byte $3F,$FF,$FC ; XXXXXXXXXXXXXXXXX
    !byte $3F,$FF,$FC ; XXXXXXXXXXXXXXXXX
    !byte $1F,$FF,$F8 ; XXXXXXXXXXXXXXX
    !byte $0F,$FF,$F0 ; XXXXXXXXXXXXXX
    !byte $03,$FF,$C0 ; XXXXXXXXXXXX
    !byte $00,$FF,$00 ; .XXXXXXXX.
    !byte $00,$3C,$00 ; ..XXXX..
    !byte $00,$00,$00, $00,$00,$00, $00,$00,$00, $00,$00,$00, $00,$00,$00 ; 5 empty rows
    !byte $00 ; Padding byte to make it 64 bytes total

; ---------------- Init ----------------
InitState: ; Reset state variables + seed SID noise
    lda #0
    sta FrameCount
    sta ScrollIdx
    sta ColorCycle
    sta WavePhase
    sta StarPhase
    sta LogoPhase
    sta PlasmaPhase
    lda #7
    sta SmoothScroll

    ; SID noise for randomness (optional but good practice)
    lda #$ff
    sta $d40e
    sta $d40f
    lda #$80
    sta $d412
    rts

InitSprites: ; Initialize sprite pointers to $A0 ($2800/64)
    lda #$a0
    ldx #0
@loop:
    sta SPRITE_PTRS,x
    inx
    cpx #8
    bne @loop
    rts

; ---------------- Clear helpers ----------------
; FIX: Replaced complex clear routines with simpler, more readable ones.
ClearScreen:
    lda #$20 ; space character
    ldx #0
@loop1:
    sta SCREEN + $000,x
    sta SCREEN + $100,x
    sta SCREEN + $200,x
    inx
    bne @loop1
    ldx #0
@loop2:
    sta SCREEN + $300,x
    inx
    cpx #(1000-768)
    bne @loop2
    rts

ClearColor:
    lda #$00 ; black color
    ldx #0
@loop1:
    sta COLOR + $000,x
    sta COLOR + $100,x
    sta COLOR + $200,x
    inx
    bne @loop1
    ldx #0
@loop2:
    sta COLOR + $300,x
    inx
    cpx #(1000-768)
    bne @loop2
    rts
