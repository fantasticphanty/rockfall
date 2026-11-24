; ============================================================
;  ROCK DODGE  -  a tiny Game Boy Color game in assembly (RGBDS)
;
;  GOAL: reach 100 points to win. You have 3 lives.
;
;  - D-pad left/right moves your ship, START pauses.
;  - Dodge rocks: 1 point each when they pass you.
;  - After 20 rocks, purple spiky METEORS (fast, 3 points)
;    and cyan GEMS (catch them for 5 points) start to fall.
;  - Every 10 rocks dodged everything falls faster (beep!).
;
;  Sound: channel 1 = sound effects, channel 2 = melody,
;         channel 3 = bass (wave), channel 4 = drums / crash.
; ============================================================

; ---- Hardware registers ------------------------------------
DEF rP1    EQU $FF00   ; joypad
DEF rDIV   EQU $FF04   ; divider (used for random seed)
DEF rIF    EQU $FF0F   ; interrupt flags
DEF rNR10  EQU $FF10   ; ch1 sweep
DEF rNR11  EQU $FF11   ; ch1 duty / length
DEF rNR12  EQU $FF12   ; ch1 volume envelope
DEF rNR13  EQU $FF13   ; ch1 frequency low
DEF rNR14  EQU $FF14   ; ch1 trigger + frequency high
DEF rNR21  EQU $FF16   ; ch2 duty / length
DEF rNR22  EQU $FF17   ; ch2 volume envelope
DEF rNR23  EQU $FF18   ; ch2 frequency low
DEF rNR24  EQU $FF19   ; ch2 trigger + frequency high
DEF rNR30  EQU $FF1A   ; ch3 on/off
DEF rNR32  EQU $FF1C   ; ch3 volume
DEF rNR33  EQU $FF1D   ; ch3 frequency low
DEF rNR34  EQU $FF1E   ; ch3 trigger + frequency high
DEF rNR41  EQU $FF20   ; ch4 length
DEF rNR42  EQU $FF21   ; ch4 volume envelope
DEF rNR43  EQU $FF22   ; ch4 noise type
DEF rNR44  EQU $FF23   ; ch4 trigger
DEF rNR50  EQU $FF24   ; master volume
DEF rNR51  EQU $FF25   ; which channels reach which speaker
DEF rNR52  EQU $FF26   ; sound on/off
DEF _WAVE  EQU $FF30   ; ch3 wave pattern (16 bytes)
DEF rLCDC  EQU $FF40   ; LCD control
DEF rLY    EQU $FF44   ; current scanline
DEF rVBK   EQU $FF4F   ; (GBC) VRAM bank select
DEF rHDMA1 EQU $FF51   ; (GBC) DMA source high
DEF rHDMA2 EQU $FF52   ; (GBC) DMA source low
DEF rHDMA3 EQU $FF53   ; (GBC) DMA destination high
DEF rHDMA4 EQU $FF54   ; (GBC) DMA destination low
DEF rHDMA5 EQU $FF55   ; (GBC) DMA length / start
DEF rBCPS  EQU $FF68   ; (GBC) BG palette index
DEF rBCPD  EQU $FF69   ; (GBC) BG palette data
DEF rOCPS  EQU $FF6A   ; (GBC) sprite palette index
DEF rOCPD  EQU $FF6B   ; (GBC) sprite palette data
DEF rIE    EQU $FFFF   ; interrupt enable

DEF _VRAM  EQU $8000
DEF _MAP0  EQU $9800
DEF _OAM   EQU $FE00

; GBC color: red, green, blue each 0-31
MACRO rgb
    dw (\1) | (\2) << 5 | (\3) << 10
ENDM

; ld_map reg, column, row  ->  map address of that tile
MACRO ld_map
    ld \1, _MAP0 + 32 * (\3) + (\2)
ENDM

; ---- Game constants ----------------------------------------
DEF GOAL_HI     EQU $01    ; win when score reaches 0100 (BCD)
DEF START_LIVES EQU 3
DEF PLAYER_Y    EQU 144    ; OAM Y (screen Y + 16)
DEF NUM_ROCKS   EQU 4
DEF ROCK_SIZE   EQU 3      ; y, x, type
DEF MAX_SPEED   EQU 4
DEF SPEEDUP_EVERY EQU 10   ; rocks dodged per speed-up
DEF SPECIALS_AT EQU 20     ; rocks dodged before meteors/gems appear
DEF HIT_TIME    EQU 75     ; frames of red flash after losing a life

DEF TYPE_ROCK   EQU 0
DEF TYPE_METEOR EQU 1
DEF TYPE_GEM    EQU 2

DEF STATE_TITLE EQU 0
DEF STATE_PLAY  EQU 1
DEF STATE_OVER  EQU 2
DEF STATE_PAUSE EQU 3
DEF STATE_HIT   EQU 4
DEF STATE_WIN   EQU 5

; BG palette numbers
DEF PAL_GROUND  EQU 0
DEF PAL_TEXT    EQU 1
DEF PAL_LOGO    EQU 2
DEF PAL_STARS   EQU 3
DEF PAL_MTN     EQU 4
DEF PAL_HUD     EQU 5
DEF NUM_BG_PALS EQU 6

DEF TILE_BLANK  EQU 0
DEF TILE_PLAYER EQU 1
DEF TILE_ROCK   EQU 2
DEF TILE_GROUND EQU 3
DEF TILE_DIGIT0 EQU 4
DEF TILE_MTN EQU 61
DEF TILE_METEOR EQU TILE_MTN + 16
DEF TILE_GEM    EQU TILE_MTN + 17
DEF TILE_STAR1  EQU TILE_MTN + 18
DEF TILE_STAR2  EQU TILE_MTN + 19

; Text: letters/digits map straight to tile numbers
CHARMAP " ", 0
CHARMAP "0", 4
CHARMAP "1", 5
CHARMAP "2", 6
CHARMAP "3", 7
CHARMAP "4", 8
CHARMAP "5", 9
CHARMAP "6", 10
CHARMAP "7", 11
CHARMAP "8", 12
CHARMAP "9", 13
CHARMAP "A", 14
CHARMAP "C", 15
CHARMAP "D", 16
CHARMAP "E", 17
CHARMAP "G", 18
CHARMAP "I", 19
CHARMAP "K", 20
CHARMAP "M", 21
CHARMAP "N", 22
CHARMAP "O", 23
CHARMAP "P", 24
CHARMAP "R", 25
CHARMAP "S", 26
CHARMAP "T", 27
CHARMAP "U", 28
CHARMAP "V", 29
CHARMAP "W", 30
CHARMAP "Y", 31
CHARMAP "!", 32

; ---- Variables (work RAM) ----------------------------------
SECTION "MountainBuffer", WRAM0, ALIGN[8]
wMtnBuf:    ds 256             ; the 16 mountain tiles, scrolled here

SECTION "Vars", WRAM0
wState:     ds 1
wFrame:     ds 1
wPlayerX:   ds 1
wRocks:     ds NUM_ROCKS * ROCK_SIZE
wScore:     ds 2               ; BCD, low byte first
wSpeed:     ds 1
wLives:     ds 1
wDodged:    ds 1               ; rocks dodged (stops at 255)
wSpeedUpIn: ds 1               ; rocks left until the next speed-up
wHitTimer:  ds 1
wJoy:       ds 1               ; buttons held this frame
wJoyPrev:   ds 1               ; buttons held last frame
wSeed:      ds 1
wMtnDirty:  ds 1               ; 1 = copy mountain tiles to VRAM
wPalKey:    ds 1               ; last palette look applied
wMusicOn:   ds 1
; each music track = timer (1 byte) + data pointer (2 bytes)
wTrkMelody: ds 3
wTrkBass:   ds 3
wTrkDrums:  ds 3

; ---- Interrupt vector --------------------------------------
SECTION "VBlank", ROM0[$0040]
    reti                       ; only used to wake from HALT

; ---- Cartridge header --------------------------------------
SECTION "Header", ROM0[$0100]
    nop
    jp Start
    ds $150 - @, 0             ; rgbfix fills in logo/checksums

; ============================================================
SECTION "Main", ROM0
Start:
    di
    ld sp, $FFFE

    call ScreenOff
    call InitSound

    ; Load tiles, and keep a working copy of the mountain tiles
    ld de, Tiles
    ld hl, _VRAM
    ld bc, TilesEnd - Tiles
    call MemCopy
    ld de, Tiles + TILE_MTN * 16
    ld hl, wMtnBuf
    ld bc, 256
    call MemCopy

    ; Clear sprite table
    ld hl, _OAM
    ld bc, 160
    xor a
    call MemSet

    ; Load sprite palettes
    ld a, $80                  ; index 0, auto-increment
    ldh [rOCPS], a
    ld hl, ObjPalettes
    ld b, ObjPalettesEnd - ObjPalettes
.objPal
    ld a, [hli]
    ldh [rOCPD], a
    dec b
    jr nz, .objPal

    xor a
    ld [wJoy], a
    ld [wJoyPrev], a
    ld [wFrame], a
    ld [wMtnDirty], a
    ld a, $FF
    ld [wPalKey], a            ; force a palette load
    ldh a, [rDIV]
    or 1
    ld [wSeed], a

    call GoToTitle

    ; Enable only the VBlank interrupt
    ld a, 1
    ldh [rIE], a
    xor a
    ldh [rIF], a
    ei

; ---- Main loop (once per frame) ----------------------------
MainLoop:
    halt                       ; sleep until VBlank
    nop

    ; --- VBlank: safe to touch VRAM / OAM / palettes ---
    call CopyMountains
    call DrawSprites
    call ApplyBGPalette
    call DrawText

    ; --- Everything else ---
    call ReadJoypad
    ld hl, wFrame
    inc [hl]

    ld a, [wState]
    cp STATE_PAUSE
    jr z, .pause
    cp STATE_HIT
    jr z, .hit
    push af
    call UpdateMusic
    call ScrollMountains
    pop af
    cp STATE_PLAY
    jr z, .play
    cp STATE_TITLE
    jr z, .title

; Game over / win: wait for START
.ended
    call StartPressed
    jp z, MainLoop
    call StartGame
    jp MainLoop

; Title screen: rocks fall in the background, wait for START
.title
    call MoveRocks
    call StartPressed
    jp z, MainLoop
    call StartGame
    jp MainLoop

.play
    call StartPressed
    jr nz, .doPause
    call MovePlayer
    call MoveRocks
    call CheckCollision
    ; Reached the goal?
    ld a, [wState]
    cp STATE_PLAY
    jp nz, MainLoop
    ld a, [wScore + 1]
    cp GOAL_HI
    jp c, MainLoop
    call WinGame
    jp MainLoop

.doPause
    ld a, STATE_PAUSE
    ld [wState], a
    ld a, %00010001
    ldh [rNR51], a             ; mute music (keep ch1 for the tick)
    call PlayPauseSfx
    jp MainLoop

.pause
    call StartPressed
    jp z, MainLoop
    ld a, STATE_PLAY
    ld [wState], a
    ld a, $FF
    ldh [rNR51], a             ; sound back on
    call PlayPauseSfx
    jp MainLoop

; Lost a life: flash for a moment, then clear the rocks and go on
.hit
    call ScrollMountains
    ld hl, wHitTimer
    dec [hl]
    jp nz, MainLoop
    call ResetRocks
    ld a, 84
    ld [wPlayerX], a
    ld a, STATE_PLAY
    ld [wState], a
    ld a, $FF
    ldh [rNR51], a             ; music back on
    jp MainLoop

; Returns NZ if START was pressed this frame (not held)
StartPressed:
    ld a, [wJoyPrev]
    cpl
    ld b, a
    ld a, [wJoy]
    and b
    and %00001000
    ret

; ============================================================
;  Screens
; ============================================================

; Waits for VBlank, then turns the LCD off (VRAM fully writable)
ScreenOff:
    ldh a, [rLCDC]
    bit 7, a
    ret z                      ; already off
.wait
    ldh a, [rLY]
    cp 144
    jr c, .wait
    xor a
    ldh [rLCDC], a
    ret

; LCD on: BG on, sprites on, BG tiles at $8000
ScreenOn:
    ld a, %10010011
    ldh [rLCDC], a
    ret

; Clears the screen and draws the scenery: stars, mountains, ground.
; LCD must be off.
DrawScenery:
    ld a, 1                    ; bank 1 = color attributes
    ldh [rVBK], a
    ld hl, _MAP0
    ld bc, 32 * 32
    xor a
    call MemSet
    xor a                      ; bank 0 = tile numbers
    ldh [rVBK], a
    ld hl, _MAP0
    ld bc, 32 * 32
    xor a
    call MemSet

    ; Stars
    ld de, StarList
.star
    ld a, [de]
    ld l, a
    inc de
    ld a, [de]
    ld h, a
    inc de
    or l
    jr z, .starsDone
    ld a, [de]                 ; tile
    inc de
    ld [hl], a
    ld a, 1
    ldh [rVBK], a
    ld [hl], PAL_STARS
    xor a
    ldh [rVBK], a
    jr .star
.starsDone

    ; Mountain ridge, rows 14-15 (tiles repeat every 8 columns)
    ld_map hl, 0, 14
    ld c, TILE_MTN
    call .mtnRow
    ld_map hl, 0, 15
    ld c, TILE_MTN + 8
    call .mtnRow
    ld a, PAL_MTN
    ld_map hl, 0, 14
    ld bc, 32 * 2
    call SetAttr

    ; Ground, row 17
    ld_map hl, 0, 17
    ld bc, 20
    ld a, TILE_GROUND
    jp MemSet

.mtnRow                        ; hl = row start, c = first tile
    ld b, 0
.mtnLoop
    ld a, b
    and 7
    add c
    ld [hli], a
    inc b
    ld a, b
    cp 32
    jr nz, .mtnLoop
    ret

MACRO STAR_AT ; column, row, tile
    dw _MAP0 + 32 * (\2) + (\1)
    db \3
ENDM
StarList:
    STAR_AT  2,  3, TILE_STAR1
    STAR_AT 17,  2, TILE_STAR2
    STAR_AT 10,  2, TILE_STAR1
    STAR_AT  3,  6, TILE_STAR2
    STAR_AT 16,  5, TILE_STAR1
    STAR_AT 13,  5, TILE_STAR1
    STAR_AT 19,  6, TILE_STAR1
    STAR_AT  1,  9, TILE_STAR1
    STAR_AT 18,  8, TILE_STAR2
    STAR_AT  8, 11, TILE_STAR1
    STAR_AT 17, 11, TILE_STAR1
    STAR_AT  2, 12, TILE_STAR2
    STAR_AT  5, 13, TILE_STAR1
    STAR_AT 15, 13, TILE_STAR2
    dw 0

; Sets the color palette of BC tiles at HL (LCD must be off)
SetAttr:                       ; a = palette, hl = map addr, bc = count
    ld e, a
    ld a, 1
    ldh [rVBK], a
    ld a, e
    call MemSet
    xor a
    ldh [rVBK], a
    ret

; Copies the mountain tiles to VRAM right now (LCD must be off)
ForceMountainCopy:
    ld a, 1
    ld [wMtnDirty], a
    ; fall through

; Copies the scrolled mountain tiles to VRAM with GBC DMA (VBlank only)
CopyMountains:
    ld a, [wMtnDirty]
    and a
    ret z
    xor a
    ld [wMtnDirty], a
    ld a, HIGH(wMtnBuf)
    ldh [rHDMA1], a
    ld a, LOW(wMtnBuf)
    ldh [rHDMA2], a
    ld a, HIGH(_VRAM + TILE_MTN * 16)
    ldh [rHDMA3], a
    ld a, LOW(_VRAM + TILE_MTN * 16)
    ldh [rHDMA4], a
    ld a, 256 / 16 - 1         ; 16 blocks of 16 bytes, copy now
    ldh [rHDMA5], a
    ret

GoToTitle:
    call ScreenOff
    call DrawScenery
    call ForceMountainCopy
    ; Big logo
    ld de, LogoRockTop
    ld_map hl, 6, 3
    ld bc, 8
    call MemCopy
    ld de, LogoRockBot
    ld_map hl, 6, 4
    ld bc, 8
    call MemCopy
    ld de, LogoDodgeTop
    ld_map hl, 5, 6
    ld bc, 10
    call MemCopy
    ld de, LogoDodgeBot
    ld_map hl, 5, 7
    ld bc, 10
    call MemCopy
    ld a, PAL_LOGO
    ld_map hl, 6, 3
    ld bc, 8
    call SetAttr
    ld a, PAL_LOGO
    ld_map hl, 6, 4
    ld bc, 8
    call SetAttr
    ld a, PAL_LOGO
    ld_map hl, 5, 6
    ld bc, 10
    call SetAttr
    ld a, PAL_LOGO
    ld_map hl, 5, 7
    ld bc, 10
    call SetAttr
    ; Goal line + PRESS START
    ld de, TxtGoal
    ld_map hl, 2, 10
    call PrintString
    ld a, PAL_TEXT
    ld_map hl, 2, 10
    ld bc, 16
    call SetAttr
    ld a, PAL_TEXT
    ld_map hl, 4, 12
    ld bc, 11
    call SetAttr

    ld a, STATE_TITLE
    ld [wState], a
    xor a
    ld [wScore], a
    ld [wScore + 1], a
    ld [wDodged], a
    ld a, 1
    ld [wSpeed], a
    call ResetRocks
    ld de, SongMain
    call StartMusic
    jp ScreenOn

StartGame:
    call PlayStartSfx
    call ScreenOff
    call DrawScenery
    call ForceMountainCopy
    ; Score, lives and the middle message rows use text palettes
    ld a, PAL_TEXT
    ld_map hl, 1, 1
    ld bc, 4
    call SetAttr
    ld a, PAL_HUD
    ld_map hl, 16, 1
    ld bc, 3
    call SetAttr
    ld a, PAL_TEXT
    ld_map hl, 4, 7
    ld bc, 12
    call SetAttr
    ld a, PAL_TEXT
    ld_map hl, 4, 8
    ld bc, 12
    call SetAttr
    ld a, PAL_TEXT
    ld_map hl, 4, 9
    ld bc, 12
    call SetAttr

    ld a, 84
    ld [wPlayerX], a
    xor a
    ld [wScore], a
    ld [wScore + 1], a
    ld [wDodged], a
    ld a, 1
    ld [wSpeed], a
    ld a, SPEEDUP_EVERY
    ld [wSpeedUpIn], a
    ld a, START_LIVES
    ld [wLives], a

    ; Mix the divider into the random seed (never zero)
    ldh a, [rDIV]
    ld b, a
    ld a, [wSeed]
    xor b
    or 1
    ld [wSeed], a

    call ResetRocks
    ld a, STATE_PLAY
    ld [wState], a
    ld a, $FF
    ldh [rNR51], a
    ld de, SongMain
    call StartMusic
    jp ScreenOn

WinGame:
    ld a, STATE_WIN
    ld [wState], a
    ld de, SongWin
    jp StartMusic

; Places all rocks above the screen, staggered, as plain rocks
ResetRocks:
    ld de, RockStartY
    ld hl, wRocks
    ld b, NUM_ROCKS
.rock
    ld a, [de]
    inc de
    ld [hli], a
    call RandomX
    ld [hli], a
    xor a
    ld [hli], a                ; TYPE_ROCK
    dec b
    jr nz, .rock
    ret

RockStartY:
    db 0, 238, 219, 200        ; 200-255 = still above the screen

; ------------------------------------------------------------
; Draws text for the current screen (VBlank only)
DrawText:
    ld a, [wState]
    cp STATE_TITLE
    jr z, .title
    push af
    call DrawScore
    call DrawLives
    pop af
    cp STATE_OVER
    jr z, .over
    cp STATE_WIN
    jr z, .win
    ; Playing / paused / hit: show or hide PAUSED
    cp STATE_PAUSE
    ld de, TxtPaused
    jr z, .paused
    ld de, TxtBlank6
.paused
    ld_map hl, 7, 8
    jr PrintString

.title
    ld_map hl, 4, 12
    jr DrawBlinkingStart

.win
    ld de, TxtYouWin
    ld_map hl, 6, 7
    jr .message
.over
    ld de, TxtGameOver
    ld_map hl, 5, 7
.message
    call PrintString
    ld_map hl, 4, 9
    ; fall through

DrawBlinkingStart:
    ld de, TxtPressStart
    ld a, [wFrame]
    and %00100000              ; on for 32 frames, off for 32
    jr nz, PrintString
    ld de, TxtBlank
    ; fall through

; Copies a $FF-terminated string from DE to the map at HL
PrintString:
    ld a, [de]
    cp $FF
    ret z
    ld [hli], a
    inc de
    jr PrintString

TxtGoal:       db "SCORE 100 TO WIN", $FF
TxtGameOver:   db "GAME OVER", $FF
TxtYouWin:     db "YOU WIN!", $FF
TxtPaused:     db "PAUSED", $FF
TxtPressStart: db "PRESS START", $FF
TxtBlank:      db "     "
TxtBlank6:     db "      ", $FF

; Draws the 4-digit score at row 1 (VBlank only)
DrawScore:
    ld_map hl, 1, 1
    ld a, [wScore + 1]
    call PutBCD
    ld a, [wScore]
    ; fall through
PutBCD:
    ld b, a
    swap a
    and $0F
    add TILE_DIGIT0
    ld [hli], a
    ld a, b
    and $0F
    add TILE_DIGIT0
    ld [hli], a
    ret

; Draws one ship icon per life, top right (VBlank only)
DrawLives:
    ld_map hl, 16, 1
    ld a, [wLives]
    ld c, a
    ld b, 3
.loop
    ld a, c
    and a
    jr z, .empty
    dec c
    ld a, TILE_PLAYER
    jr .put
.empty
    xor a
.put
    ld [hli], a
    dec b
    jr nz, .loop
    ret

; ============================================================
;  Gameplay
; ============================================================

; Reads the joypad into wJoy.
; Bits: 7 Down 6 Up 5 Left 4 Right 3 Start 2 Select 1 B 0 A
ReadJoypad:
    ld a, $20                  ; select D-pad
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    swap a
    ld b, a

    ld a, $10                  ; select buttons
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    or b
    ld b, a

    ld a, $30                  ; deselect
    ldh [rP1], a

    ld a, [wJoy]
    ld [wJoyPrev], a
    ld a, b
    ld [wJoy], a
    ret

MovePlayer:
    ld a, [wJoy]
    ld b, a
    ld a, [wPlayerX]
    bit 5, b                   ; Left
    jr z, .noLeft
    cp 10
    jr c, .noLeft
    sub 2
.noLeft
    bit 4, b                   ; Right
    jr z, .noRight
    cp 159
    jr nc, .noRight
    add 2
.noRight
    ld [wPlayerX], a
    ret

MoveRocks:
    ld hl, wRocks
    ld b, NUM_ROCKS
.loop
    ; Meteors fall 1 pixel/frame faster than everything else
    ld a, [wSpeed]
    ld c, a
    inc hl
    inc hl
    ld a, [hld]                ; type
    dec hl
    cp TYPE_METEOR
    jr nz, .notMeteor
    inc c
.notMeteor
    ld a, [hl]
    add c
    ld [hl], a
    ; Fell past the bottom? (160 <= y < 200)
    cp 160
    jr c, .next
    cp 200
    jr nc, .next

    ; Dodged it! Score it, then respawn it above the screen
    push bc
    push hl
    inc hl
    inc hl
    ld a, [hl]                 ; type
    cp TYPE_GEM
    jr z, .missedGem           ; letting a gem fall is no points
    ld e, a
    ld d, 0
    ld hl, DodgePoints
    add hl, de
    ld a, [hl]
    call AddScore
    call CountDodge
.missedGem
    pop hl
    push hl
    call SpawnRock
    pop hl
    pop bc
.next
    inc hl
    inc hl
    inc hl
    dec b
    jr nz, .loop
    ret

DodgePoints:
    db 1, 3, 0                 ; rock, meteor, gem (BCD)

; HL = rock. New random position above the screen and a random type.
SpawnRock:
    call Random
    and 31
    add 200
    ld [hli], a
    call RandomX
    ld [hli], a
    ; Specials only once enough rocks have been dodged
    ld a, [wDodged]
    cp SPECIALS_AT
    ld a, TYPE_ROCK
    jr c, .setType
    call Random
    and 7
    cp 2                       ; 0-1: meteor (25%)
    ld a, TYPE_METEOR
    jr c, .setType
    jr nz, .plain              ; 3-7: rock
    ld a, TYPE_GEM             ; 2: gem (12.5%)
    jr .setType
.plain
    ld a, TYPE_ROCK
.setType
    ld [hl], a
    ret

; +A points (BCD, 1-9). Only counts while playing.
AddScore:
    ld b, a
    ld a, [wState]
    cp STATE_PLAY
    ret nz
    ld a, [wScore]
    add b
    daa
    ld [wScore], a
    ld a, [wScore + 1]
    adc 0
    daa
    ld [wScore + 1], a
    jp PlayScoreSfx

; One more rock dodged: maybe speed up
CountDodge:
    ld a, [wState]
    cp STATE_PLAY
    ret nz
    ld a, [wDodged]
    inc a
    jr z, .capped
    ld [wDodged], a
.capped
    ld hl, wSpeedUpIn
    dec [hl]
    ret nz
    ld [hl], SPEEDUP_EVERY
    ld a, [wSpeed]
    cp MAX_SPEED
    ret nc
    inc a
    ld [wSpeed], a
    jp PlaySpeedUpSfx

CheckCollision:
    ld hl, wRocks
    ld b, NUM_ROCKS
.loop
    ld a, [hl]                 ; rock Y
    sub PLAYER_Y
    jr nc, .yPos
    cpl
    inc a
.yPos
    cp 7
    jr nc, .next

    inc hl
    ld a, [wPlayerX]
    ld c, a
    ld a, [hld]                ; rock X
    sub c
    jr nc, .xPos
    cpl
    inc a
.xPos
    cp 7
    jr nc, .next

    ; Touching it. A gem is caught, anything else hurts.
    push hl
    inc hl
    inc hl
    ld a, [hl]
    pop hl
    cp TYPE_GEM
    jr nz, .hurt
    push bc
    push hl
    call PlayGemSfx
    ld a, 5
    call AddScore
    pop hl
    push hl
    call SpawnRock
    pop hl
    pop bc
    jr .next

.hurt
    call PlayCrashSfx
    ld hl, wLives
    dec [hl]
    jr z, .gameOver
    ld a, HIT_TIME
    ld [wHitTimer], a
    ld a, STATE_HIT
    ld [wState], a
    ld a, %10011001            ; only sound effects (ch1 + ch4) audible
    ldh [rNR51], a
    ret
.gameOver
    ld a, STATE_OVER
    ld [wState], a
    jp StopMusic

.next
    inc hl
    inc hl
    inc hl
    dec b
    jr nz, .loop
    ret

; Writes the player + rocks straight into OAM (VBlank only)
DrawSprites:
    ld hl, _OAM
    ld a, [wState]
    cp STATE_TITLE
    ld a, PLAYER_Y
    jr nz, .showPlayer
    xor a                      ; Y=0 hides the ship on the title
.showPlayer
    ld [hli], a
    ld a, [wPlayerX]
    ld [hli], a
    ld a, TILE_PLAYER
    ld [hli], a
    xor a
    ld [hli], a

    ld de, wRocks
    ld b, NUM_ROCKS
.loop
    ld a, [de]                 ; y
    inc de
    ld [hli], a
    ld a, [de]                 ; x
    inc de
    ld [hli], a
    ld a, [de]                 ; type -> tile + palette
    inc de
    push de
    ld e, a
    ld d, 0
    push hl
    ld hl, TypeTiles
    add hl, de
    ld c, [hl]
    ld hl, TypePalettes
    add hl, de
    ld a, [hl]
    pop hl
    pop de
    ld [hl], c
    inc hl
    ld [hli], a
    dec b
    jr nz, .loop
    ret

TypeTiles:    db TILE_ROCK, TILE_METEOR, TILE_GEM
TypePalettes: db 1, 2, 3

; ------------------------------------------------------------
; Scrolls the mountain outline 1 pixel left every 4 frames.
; Each pixel row is 8 tiles wide; rotate those 8 bytes as one
; 64-bit number (only bitplane 0 is used by the outline).
ScrollMountains:
    ld a, [wFrame]
    and 3
    ret nz
    ld b, 0                    ; byte offset of this pixel row in tile 0
    ld c, 16                   ; pixel rows
    ld h, HIGH(wMtnBuf)
.row
    ld d, h
    ld e, b
    ld a, b
    add 7 * 16                 ; tile 7, same row
    ld l, a
    ld a, [de]                 ; leftmost byte
    rla                        ; carry = leftmost pixel (wraps around)
    REPT 7
        rl [hl]
        push af
        ld a, l
        sub 16
        ld l, a
        pop af
    ENDR
    rl [hl]
    ; next pixel row: +2 bytes, jumping to the lower tile row after 8
    ld a, b
    add 2
    cp 16
    jr nz, .sameTileRow
    ld a, 128
.sameTileRow
    ld b, a
    dec c
    jr nz, .row
    ld a, 1
    ld [wMtnDirty], a
    ret

; ------------------------------------------------------------
; Loads BG palettes when the look changes: normal, red flash
; (hit / game over), green (win), and twinkling stars.
ApplyBGPalette:
    ; key = bit 5 of frame (star twinkle) + flash mode in bits 0-1
    ld a, [wFrame]
    and %00100000
    ld b, a
    ld a, [wState]
    cp STATE_OVER
    ld c, 1
    jr z, .gotMode
    cp STATE_WIN
    ld c, 2
    jr z, .gotMode
    ld c, 0
    cp STATE_HIT
    jr nz, .gotMode
    ld a, [wFrame]
    and %00000100              ; blink while hit
    jr z, .gotMode
    ld c, 1
.gotMode
    ld a, b
    or c
    ld hl, wPalKey
    cp [hl]
    ret z                      ; nothing changed
    ld [hl], a

    ld a, $80
    ldh [rBCPS], a
    ld hl, BGPalettes
    ld b, NUM_BG_PALS * 8
.copy
    ld a, [hli]
    ldh [rBCPD], a
    dec b
    jr nz, .copy

    ; Flash: replace the background color of every palette
    ld a, c
    and a
    jr z, .stars
    ld de, RGB_RED
    dec a
    jr z, .flash
    ld de, RGB_GREEN
.flash
    ld b, NUM_BG_PALS
    ld a, $80
.flashLoop
    ldh [rBCPS], a
    ld h, a
    ld a, e
    ldh [rBCPD], a
    ld a, d
    ldh [rBCPD], a
    ld a, h
    add 8
    dec b
    jr nz, .flashLoop

.stars
    ; Swap the two star brightnesses every 32 frames
    ld a, [wPalKey]
    and %00100000
    ret z
    ld a, $80 | (PAL_STARS * 8 + 2)
    ldh [rBCPS], a
    ld a, LOW(RGB_STAR_BRIGHT)
    ldh [rBCPD], a
    ld a, HIGH(RGB_STAR_BRIGHT)
    ldh [rBCPD], a
    ld a, LOW(RGB_STAR_DIM)
    ldh [rBCPD], a
    ld a, HIGH(RGB_STAR_DIM)
    ldh [rBCPD], a
    ret

DEF RGB_RED         EQU 16
DEF RGB_GREEN       EQU (9 << 5) | (3 << 10)
DEF RGB_STAR_DIM    EQU 9 | (9 << 5) | (14 << 10)
DEF RGB_STAR_BRIGHT EQU 31 | (31 << 5) | (31 << 10)

; ============================================================
;  Sound
; ============================================================
InitSound:
    ld a, $80
    ldh [rNR52], a             ; sound on
    ld a, $77
    ldh [rNR50], a             ; full volume
    ld a, $FF
    ldh [rNR51], a             ; every channel to both speakers
    xor a
    ldh [rNR30], a             ; ch3 off while loading the wave
    ld de, BassWave
    ld hl, _WAVE
    ld bc, 16
    call MemCopy
    xor a
    ld [wMusicOn], a
    ret

; DE = song (3 track addresses: melody, bass, drums)
StartMusic:
    ld hl, wTrkMelody
    ld b, 3
.track
    ld a, 1                    ; timer = 1 -> first note plays next frame
    ld [hli], a
    ld a, [de]
    inc de
    ld [hli], a
    ld a, [de]
    inc de
    ld [hli], a
    dec b
    jr nz, .track
    ld a, 1
    ld [wMusicOn], a
    ret

SongMain: dw MusicMelody, MusicBass, MusicDrums
SongWin:  dw WinMelody, WinBass, WinDrums

StopMusic:
    xor a
    ld [wMusicOn], a
    ldh [rNR22], a             ; silence melody
    ld a, $80
    ldh [rNR24], a
    xor a
    ldh [rNR32], a             ; silence bass
    ret

UpdateMusic:
    ld a, [wMusicOn]
    and a
    ret z
    ld hl, wTrkMelody
    call NextNote
    call nc, PlayMelody
    ld hl, wTrkBass
    call NextNote
    call nc, PlayBass
    ld hl, wTrkDrums
    call NextNote
    call nc, PlayDrum
    ret

; Advances one track. HL = track. If a new note starts this frame,
; returns carry clear with the note in A; otherwise carry set.
NextNote:
    dec [hl]
    scf
    ret nz
    push hl
    inc hl
    ld a, [hli]
    ld d, [hl]
    ld e, a                    ; de = data pointer
    ld a, [de]
    cp $FE                     ; end of a one-shot song
    jr z, .end
    cp $FF                     ; end of a looping song -> back to start
    jr nz, .note
    inc de
    ld a, [de]
    ld c, a
    inc de
    ld a, [de]
    ld d, a
    ld e, c
    ld a, [de]
.note
    ld b, a                    ; b = note
    inc de
    ld a, [de]
    ld c, a                    ; c = length in frames
    inc de
    ld a, d                    ; save pointer
    ld [hld], a
    ld a, e
    ld [hld], a
    ld [hl], c                 ; timer = length
    pop hl
    ld a, b
    and a                      ; clears carry
    ret
.end
    pop hl
    ld [hl], 1                 ; keep re-checking harmlessly
    call StopMusic
    scf
    ret

; HL <- note frequency for note A
NoteFreq:
    ld hl, NoteTable
    add a
    ld e, a
    ld d, 0
    add hl, de
    ret

PlayMelody:                    ; channel 2, square wave
    and a
    jr z, .rest
    call NoteFreq
    ld a, $80                  ; 50% duty
    ldh [rNR21], a
    ld a, $93                  ; volume 9, fade out
    ldh [rNR22], a
    ld a, [hli]
    ldh [rNR23], a
    ld a, [hl]
    or $80                     ; trigger
    ldh [rNR24], a
    ret
.rest
    ldh [rNR22], a
    ld a, $80
    ldh [rNR24], a
    ret

PlayBass:                      ; channel 3, wave (plays an octave lower)
    and a
    jr z, .rest
    call NoteFreq
    ld a, $80
    ldh [rNR30], a
    ld a, $20                  ; full wave volume
    ldh [rNR32], a
    ld a, [hli]
    ldh [rNR33], a
    ld a, [hl]
    or $80
    ldh [rNR34], a
    ret
.rest
    ldh [rNR32], a
    ret

PlayDrum:                      ; channel 4, noise. 1 = snare, 2 = hi-hat
    and a
    ret z
    cp 1
    ld a, $B1                  ; snare: louder, longer
    ld b, $32
    jr z, .hit
    ld a, $41                  ; hi-hat: quiet, short, bright
    ld b, $00
.hit
    ldh [rNR42], a
    ld a, b
    ldh [rNR43], a
    xor a
    ldh [rNR41], a
    ld a, $80
    ldh [rNR44], a
    ret

; Sound effects on channel 1 (a = sweep, b = envelope, de = freq)
PlayScoreSfx:                  ; quick rising blip
    ld a, $15
    ld b, $A1
    ld de, $879C
    jr Ch1Sfx
PlayGemSfx:                    ; bright sparkle
    ld a, $14
    ld b, $D2
    ld de, $87AC
    jr Ch1Sfx
PlaySpeedUpSfx:                ; soft high beep
    xor a
    ld b, $62
    ld de, $8783
    jr Ch1Sfx
PlayPauseSfx:                  ; short neutral tick
    xor a
    ld b, $81
    ld de, $8721
    jr Ch1Sfx
PlayStartSfx:                  ; long rising "whoop"
    ld a, $26
    ld b, $F3
    ld de, $8705
    jr Ch1Sfx
PlayCrashSfx:                  ; falling tone + noise explosion
    ld a, $F4
    ldh [rNR42], a
    ld a, $71
    ldh [rNR43], a
    xor a
    ldh [rNR41], a
    ld a, $80
    ldh [rNR44], a
    ld a, $7F
    ld b, $F4
    ld de, $86D6
    ; fall through
Ch1Sfx:
    ldh [rNR10], a
    ld a, $80
    ldh [rNR11], a
    ld a, b
    ldh [rNR12], a
    ld a, e
    ldh [rNR13], a
    ld a, d
    ldh [rNR14], a
    ret

; ============================================================
;  Helpers
; ============================================================

; 8-bit Galois LFSR. Returns a random number in A.
Random:
    ld a, [wSeed]
    sla a
    jr nc, .noXor
    xor $1D
.noXor
    ld [wSeed], a
    ret

; Random sprite X in 8..159 (on-screen)
RandomX:
    call Random
    cp 152
    jr nc, RandomX
    add 8
    ret

MemCopy:                       ; de = src, hl = dst, bc = length
    ld a, [de]
    ld [hli], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, MemCopy
    ret

MemSet:                        ; a = value, hl = dst, bc = length
    ld d, a
.loop
    ld a, d
    ld [hli], a
    dec bc
    ld a, b
    or c
    jr nz, .loop
    ret

; ============================================================
;  Colors
; ============================================================
SECTION "Palettes", ROM0
BGPalettes:
    ; 0: ground       (black, deep blue, magenta, cyan)
    rgb  0,  0,  0
    rgb  4,  6, 20
    rgb 31,  0, 24
    rgb  0, 31, 31
    ; 1: text / score (black, -, -, yellow)
    rgb  0,  0,  0
    rgb  0,  0,  0
    rgb  0,  0,  0
    rgb 31, 31,  0
    ; 2: title logo   (black, red shadow, orange, yellow)
    rgb  0,  0,  0
    rgb 24,  0,  4
    rgb 31, 14,  0
    rgb 31, 31,  4
    ; 3: stars        (black, star A, star B, -)
    rgb  0,  0,  0
    rgb  9,  9, 14
    rgb 31, 31, 31
    rgb  0,  0,  0
    ; 4: mountains    (black, dim violet outline, -, -)
    rgb  0,  0,  0
    rgb 10,  5, 17
    rgb  0,  0,  0
    rgb  0,  0,  0
    ; 5: lives icons  (black, white, -, lime)
    rgb  0,  0,  0
    rgb 31, 31, 31
    rgb  0,  0,  0
    rgb  8, 31,  4

ObjPalettes:
    ; 0: player       (transparent, white, -, lime)
    rgb  0,  0,  0
    rgb 31, 31, 31
    rgb  0,  0,  0
    rgb  8, 31,  4
    ; 1: rock         (transparent, yellow, orange, red)
    rgb  0,  0,  0
    rgb 31, 31,  0
    rgb 31, 14,  0
    rgb 31,  2,  2
    ; 2: meteor       (transparent, white, pink, purple)
    rgb  0,  0,  0
    rgb 31, 31, 31
    rgb 31,  8, 24
    rgb 18,  0, 31
    ; 3: gem          (transparent, white, cyan, blue)
    rgb  0,  0,  0
    rgb 31, 31, 31
    rgb  4, 28, 31
    rgb  2,  8, 31
ObjPalettesEnd:

; ============================================================
;  Music data
;  Each entry: note number (0 = rest), length in frames.
;  $FF + address = loop back, $FE = stop.
; ============================================================
SECTION "Music", ROM0
; Bass wave shape (32 samples, 4 bits each): soft triangle
BassWave:
    db $01, $23, $45, $67, $89, $AB, $CD, $EF
    db $FE, $DC, $BA, $98, $76, $54, $32, $10

; Note frequencies, starting at C2 (note 1)
NoteTable:
    dw 0                       ; 0 = rest
    dw 44
    dw 157
    dw 263
    dw 363
    dw 457
    dw 547
    dw 631
    dw 711
    dw 786
    dw 856
    dw 923
    dw 986
    dw 1046
    dw 1102
    dw 1155
    dw 1205
    dw 1253
    dw 1297
    dw 1339
    dw 1379
    dw 1417
    dw 1452
    dw 1486
    dw 1517
    dw 1547
    dw 1575
    dw 1602
    dw 1627
    dw 1650
    dw 1673
    dw 1694
    dw 1714
    dw 1732
    dw 1750
    dw 1767
    dw 1783
    dw 1798
    dw 1812
    dw 1825
    dw 1837
    dw 1849
    dw 1860
    dw 1871
    dw 1881
    dw 1890
    dw 1899
    dw 1907
    dw 1915
    dw 1923
    dw 1930
    dw 1936
    dw 1943
    dw 1949
    dw 1954
    dw 1959
    dw 1964
    dw 1969
    dw 1974
    dw 1978
    dw 1982
    dw 1985

MusicMelody:
    db 34,8, 37,8, 41,8, 46,8, 44,8, 41,8, 37,8, 41,8
    db 30,8, 34,8, 37,8, 42,8, 41,8, 37,8, 34,8, 37,8
    db 32,8, 36,8, 39,8, 44,8, 42,8, 39,8, 36,8, 39,8
    db 41,8, 33,8, 36,8, 41,8, 45,8, 41,8, 36,8, 33,8
    db 34,8, 37,8, 41,8, 46,8, 44,8, 41,8, 37,8, 41,8
    db 30,8, 34,8, 37,8, 42,8, 41,8, 37,8, 34,8, 37,8
    db 32,8, 36,8, 39,8, 44,8, 48,8, 44,8, 39,8, 36,8
    db 46,16, 41,8, 37,8, 34,16, 0,16, 49,16, 48,8, 46,8
    db 44,16, 41,16, 42,16, 41,8, 39,8, 37,16, 34,16, 39,16
    db 37,8, 36,8, 32,16, 36,16, 41,24, 39,8, 37,8, 36,8
    db 33,8, 36,8, 49,16, 48,8, 46,8, 44,16, 41,16, 42,16
    db 46,8, 42,8, 41,16, 37,16, 39,8, 41,8, 42,8, 44,8
    db 46,8, 48,8, 49,8, 48,8, 36,8, 39,8, 41,8, 45,8
    db 48,32
    db $FF
    dw MusicMelody

MusicBass:
    db 22,8, 34,8, 22,8, 34,8, 22,8, 34,8, 22,8, 34,8
    db 18,8, 30,8, 18,8, 30,8, 18,8, 30,8, 18,8, 30,8
    db 20,8, 32,8, 20,8, 32,8, 20,8, 32,8, 20,8, 32,8
    db 17,8, 29,8, 17,8, 29,8, 17,8, 29,8, 17,8, 29,8
    db 22,8, 34,8, 22,8, 34,8, 22,8, 34,8, 22,8, 34,8
    db 18,8, 30,8, 18,8, 30,8, 18,8, 30,8, 18,8, 30,8
    db 20,8, 32,8, 20,8, 32,8, 20,8, 32,8, 20,8, 32,8
    db 17,8, 29,8, 17,8, 29,8, 17,8, 29,8, 17,8, 29,8
    db 22,8, 34,8, 22,8, 34,8, 22,8, 34,8, 22,8, 34,8
    db 18,8, 30,8, 18,8, 30,8, 18,8, 30,8, 18,8, 30,8
    db 20,8, 32,8, 20,8, 32,8, 20,8, 32,8, 20,8, 32,8
    db 17,8, 29,8, 17,8, 29,8, 17,8, 29,8, 17,8, 29,8
    db 22,8, 34,8, 22,8, 34,8, 22,8, 34,8, 22,8, 34,8
    db 18,8, 30,8, 18,8, 30,8, 18,8, 30,8, 18,8, 30,8
    db 20,8, 32,8, 20,8, 32,8, 20,8, 32,8, 20,8, 32,8
    db 17,8, 29,8, 17,8, 29,8, 17,8, 29,8, 17,8, 29,8
    db $FF
    dw MusicBass

MusicDrums:
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 2,8, 2,8, 1,8, 2,8, 2,8, 2,8, 1,8, 2,8
    db 1,8, 1,8, 1,8, 1,8, 1,8, 2,8, 1,8, 1,8
    db $FF
    dw MusicDrums

WinMelody:
    db 32,8, 37,8, 41,8, 44,16, 41,8, 44,16, 34,8, 39,8
    db 42,8, 46,16, 42,8, 46,16, 36,8, 39,8, 44,8, 48,16
    db 51,16, 48,8, 49,48, 0,16
    db $FE                       ; end

WinBass:
    db 13,8, 25,8, 13,8, 25,8, 13,8, 25,8, 13,8, 25,8
    db 15,8, 27,8, 15,8, 27,8, 15,8, 27,8, 15,8, 27,8
    db 20,8, 32,8, 20,8, 32,8, 20,8, 32,8, 20,8, 32,8
    db 13,48, 0,16
    db $FE                       ; end

WinDrums:
    db 1,8, 2,8, 1,8, 2,8, 1,8, 2,8, 1,8, 1,8
    db 1,8, 2,8, 1,8, 2,8, 1,8, 2,8, 1,8, 1,8
    db 1,8, 2,8, 1,8, 2,8, 1,8, 2,8, 1,8, 1,8
    db 1,48, 0,16
    db $FE                       ; end

; ============================================================
;  Graphics (8x8 tiles, color index 0-3 into the palettes)
; ============================================================
SECTION "Tiles", ROM0
Tiles:
    ; 0: blank
    ds 16, 0

    ; 1: player ship
    dw `00033000
    dw `00033000
    dw `00311300
    dw `03311330
    dw `33333333
    dw `33333333
    dw `03300330
    dw `03000030

    ; 2: rock
    dw `00222200
    dw `02233320
    dw `22333332
    dw `23331332
    dw `23333312
    dw `22313322
    dw `02222220
    dw `00222200

    ; 3: ground
    dw `33333333
    dw `21212121
    dw `12121212
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111

    ; 4-13: digits 0-9
    dw `00333300, `03300330, `03300330, `03300330, `03300330, `03300330, `00333300, `00000000
    dw `00033000, `00333000, `00033000, `00033000, `00033000, `00033000, `00333300, `00000000
    dw `00333300, `03300330, `00000330, `00033300, `00330000, `03300000, `03333330, `00000000
    dw `00333300, `03300330, `00000330, `00033300, `00000330, `03300330, `00333300, `00000000
    dw `00003300, `00033300, `00303300, `03003300, `03333330, `00003300, `00003300, `00000000
    dw `03333330, `03300000, `03333300, `00000330, `00000330, `03300330, `00333300, `00000000
    dw `00333300, `03300000, `03333300, `03300330, `03300330, `03300330, `00333300, `00000000
    dw `03333330, `00000330, `00003300, `00033000, `00330000, `00330000, `00330000, `00000000
    dw `00333300, `03300330, `03300330, `00333300, `03300330, `03300330, `00333300, `00000000
    dw `00333300, `03300330, `03300330, `00333330, `00000330, `00000330, `00333300, `00000000

    ; 14+: letters, big logo letters (4 tiles each), mountain outline (16)
    ; A  (tile 14)
    dw `00333300, `03300330, `03300330, `03333330, `03300330, `03300330, `03300330, `00000000
    ; C  (tile 15)
    dw `00333300, `03300330, `03300000, `03300000, `03300000, `03300330, `00333300, `00000000
    ; D  (tile 16)
    dw `03333300, `03300330, `03300330, `03300330, `03300330, `03300330, `03333300, `00000000
    ; E  (tile 17)
    dw `03333330, `03300000, `03300000, `03333300, `03300000, `03300000, `03333330, `00000000
    ; G  (tile 18)
    dw `00333300, `03300330, `03300000, `03333330, `03300330, `03300330, `00333330, `00000000
    ; I  (tile 19)
    dw `00333300, `00033000, `00033000, `00033000, `00033000, `00033000, `00333300, `00000000
    ; K  (tile 20)
    dw `03300330, `03303300, `03333000, `03330000, `03333000, `03303300, `03300330, `00000000
    ; M  (tile 21)
    dw `03300330, `03333330, `03333330, `03333330, `03300330, `03300330, `03300330, `00000000
    ; N  (tile 22)
    dw `03300330, `03330330, `03333330, `03303330, `03300330, `03300330, `03300330, `00000000
    ; O  (tile 23)
    dw `00333300, `03300330, `03300330, `03300330, `03300330, `03300330, `00333300, `00000000
    ; P  (tile 24)
    dw `03333300, `03300330, `03300330, `03333300, `03300000, `03300000, `03300000, `00000000
    ; R  (tile 25)
    dw `03333300, `03300330, `03300330, `03333300, `03333000, `03303300, `03300330, `00000000
    ; S  (tile 26)
    dw `00333330, `03300000, `03300000, `00333300, `00000330, `00000330, `03333300, `00000000
    ; T  (tile 27)
    dw `03333330, `00033000, `00033000, `00033000, `00033000, `00033000, `00033000, `00000000
    ; U  (tile 28)
    dw `03300330, `03300330, `03300330, `03300330, `03300330, `03300330, `00333300, `00000000
    ; V  (tile 29)
    dw `03300330, `03300330, `03300330, `03300330, `03300330, `00333300, `00033000, `00000000
    ; W  (tile 30)
    dw `03300330, `03300330, `03300330, `03333330, `03333330, `03333330, `03300330, `00000000
    ; Y  (tile 31)
    dw `03300330, `03300330, `00333300, `00033000, `00033000, `00033000, `00033000, `00000000
    ; !  (tile 32)
    dw `00033000, `00033000, `00033000, `00033000, `00033000, `00000000, `00033000, `00000000
    ; big R part 0
    dw `00000000, `33333333, `33333333, `33331111, `33331000, `33331000, `33331000, `33333333
    ; big R part 1
    dw `00000000, `33330000, `33331000, `11333300, `00333310, `00333310, `00333310, `33331110
    ; big R part 2
    dw `22222222, `22221122, `22221022, `22221001, `22221000, `22221000, `22221000, `01111000
    ; big R part 3
    dw `22221000, `22111000, `22100000, `22220000, `22221000, `01222200, `00222210, `00011110
    ; big O part 0
    dw `00000000, `00333333, `00333333, `33331111, `33331000, `33331000, `33331000, `33331000
    ; big O part 1
    dw `00000000, `33330000, `33331000, `11333300, `00333310, `00333310, `00333310, `00333310
    ; big O part 2
    dw `22221000, `22221000, `22221000, `22221000, `22221000, `01222222, `00222222, `00011111
    ; big O part 3
    dw `00222210, `00222210, `00222210, `00222210, `00222210, `22221110, `22221000, `11111000
    ; big C part 0
    dw `00000000, `00333333, `00333333, `33331111, `33331000, `33331000, `33331000, `33331000
    ; big C part 1
    dw `00000000, `33330000, `33331000, `11333300, `00333310, `00011110, `00000000, `00000000
    ; big C part 2
    dw `22221000, `22221000, `22221000, `22221000, `22221000, `01222222, `00222222, `00011111
    ; big C part 3
    dw `00000000, `00000000, `00000000, `00222200, `00222210, `22221110, `22221000, `11111000
    ; big K part 0
    dw `00000000, `33330000, `33331000, `33331000, `33331000, `33331033, `33331033, `33333333
    ; big K part 1
    dw `00000000, `00333300, `00333310, `33331110, `33331000, `33111000, `33100000, `11100000
    ; big K part 2
    dw `22222222, `22221122, `22221022, `22221001, `22221000, `22221000, `22221000, `01111000
    ; big K part 3
    dw `10000000, `22000000, `22100000, `22220000, `22221000, `01222200, `00222210, `00011110
    ; big D part 0
    dw `00000000, `33333333, `33333333, `33331111, `33331000, `33331000, `33331000, `33331000
    ; big D part 1
    dw `00000000, `33000000, `33100000, `33330000, `33331000, `01333300, `00333310, `00333310
    ; big D part 2
    dw `22221000, `22221000, `22221000, `22221000, `22221000, `22222222, `22222222, `01111111
    ; big D part 3
    dw `00222210, `00222210, `00222210, `22221110, `22221000, `22111000, `22100000, `11100000
    ; big G part 0
    dw `00000000, `00333333, `00333333, `33331111, `33331000, `33331000, `33331000, `33331000
    ; big G part 1
    dw `00000000, `33330000, `33331000, `11333300, `00333310, `00011110, `00000000, `33333300
    ; big G part 2
    dw `22221000, `22221000, `22221000, `22221000, `22221000, `01222222, `00222222, `00011111
    ; big G part 3
    dw `22222210, `01222210, `00222210, `00222210, `00222210, `22222210, `22222210, `11111110
    ; big E part 0
    dw `00000000, `33333333, `33333333, `33331111, `33331000, `33331000, `33331000, `33333333
    ; big E part 1
    dw `00000000, `33333300, `33333310, `11111110, `00000000, `00000000, `00000000, `33330000
    ; big E part 2
    dw `22222222, `22221111, `22221000, `22221000, `22221000, `22222222, `22222222, `01111111
    ; big E part 3
    dw `22221000, `11111000, `00000000, `00000000, `00000000, `22222200, `22222210, `11111110
    ; mountain 0
    dw `00000000, `00000000, `00000000, `00000000, `01110000, `10001100, `00000010, `00000001
    ; mountain 1
    dw `00000000, `00000000, `00000000, `00000000, `00000000, `00000011, `00000100, `00001000
    ; mountain 2
    dw `00000000, `00000000, `00000000, `00000000, `11110000, `00001000, `00000110, `00000001
    ; mountain 3
    dw `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000
    ; mountain 4
    dw `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000
    ; mountain 5
    dw `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000
    ; mountain 6
    dw `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000
    ; mountain 7
    dw `00000000, `00000000, `00000000, `00000000, `00000000, `00000001, `00000010, `00001100
    ; mountain 8
    dw `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000
    ; mountain 9
    dw `11110000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000
    ; mountain 10
    dw `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000, `00000000
    ; mountain 11
    dw `10000000, `01100000, `00010000, `00001100, `00000010, `00000001, `00000000, `00000000
    ; mountain 12
    dw `00000000, `00000000, `00000000, `00000001, `00000010, `10001100, `01110000, `00000000
    ; mountain 13
    dw `00000000, `00000000, `11110000, `00001000, `00000100, `00000011, `00000000, `00000000
    ; mountain 14
    dw `00000000, `00000000, `00000000, `00000001, `00000110, `00001000, `11110000, `00000000
    ; mountain 15
    dw `00010000, `01100000, `10000000, `00000000, `00000000, `00000000, `00000000, `00000000

    ; meteor (spiky)
    dw `00030000
    dw `30033003
    dw `03322330
    dw `00321230
    dw `03321233
    dw `03322330
    dw `30033003
    dw `00003000

    ; gem
    dw `00333300
    dw `03112230
    dw `31122223
    dw `32222223
    dw `03222230
    dw `00322300
    dw `00033000
    dw `00000000

    ; star 1 (tiny)
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00010000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    ; star 2 (small cross)
    dw `00000000
    dw `00000000
    dw `00020000
    dw `00222000
    dw `00020000
    dw `00000000
    dw `00000000
    dw `00000000
TilesEnd:

; Logo layout (tile numbers)
LogoRockTop:
    db 33, 34, 37, 38, 41, 42, 45, 46
LogoRockBot:
    db 35, 36, 39, 40, 43, 44, 47, 48
LogoDodgeTop:
    db 49, 50, 37, 38, 49, 50, 53, 54, 57, 58
LogoDodgeBot:
    db 51, 52, 39, 40, 51, 52, 55, 56, 59, 60
