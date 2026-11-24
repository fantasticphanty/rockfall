# Rock Dodge — a Game Boy Color game in assembly

## How to play
**Goal: reach 100 points to win.** You start with 3 lives (the ship icons, top right).

| Falls from the sky | What to do | Points |
|---|---|---|
| Red/orange **rock** | Dodge it | 1 when it passes you |
| Purple spiky **meteor** (after 20 rocks, falls faster) | Dodge it | 3 when it passes you |
| Cyan **gem** (after 20 rocks) | Catch it! (it's harmless) | 5 |

- Every 10 rocks you dodge, everything falls faster (up to 4 speed levels), and a
  soft beep tells you it's coming.
- Getting hit by a rock or meteor costs a life: the screen flashes red, the sky
  clears, and play continues. Lose all 3 and it's GAME OVER.
- Hit 100 points and you get the YOU WIN screen and a victory fanfare.

**Controls:** D-pad Left/Right to move · START to begin, pause/unpause, or play again.

Includes a looping chiptune soundtrack (melody, bass, drums), sound effects for
points, gems, speed-ups, pausing, starting and crashing, and a slowly scrolling
mountain-ridge outline with twinkling stars in the background.

## Files
- `rockdodge.asm` — the full source (Game Boy / Sharp LR35902 assembly, RGBDS syntax)
- `rockdodge.gb` — the ROM, already built, ready to play

## 1. Install the tools (Mac)

You need Homebrew. If you don't have it, paste this in Terminal first:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then install the RGBDS assembler and the SameBoy emulator:

```
brew install rgbds
brew install --cask sameboy
```

## 2. Compile

Put `rockdodge.asm` in a folder, `cd` into it in Terminal, and run:

```
rgbasm -o rockdodge.o rockdodge.asm
rgblink -o rockdodge.gb rockdodge.o
rgbfix -v -C -p 0xFF -t "ROCKDODGE" rockdodge.gb
```

- `rgbasm` assembles the source into an object file
- `rgblink` links it into a ROM
- `rgbfix` writes the Nintendo logo and checksums into the header (real hardware
  and most emulators refuse to boot without them)
- `-C` marks the ROM as Game Boy Color, which is what unlocks the bright colors

## 3. Run

```
open -a SameBoy rockdodge.gb
```

Or just double-click `rockdodge.gb` / drag it onto the SameBoy window.
SameBoy keys: arrow keys = D-pad, Enter = START (change in SameBoy > Preferences).

If macOS says SameBoy "can't be opened", right-click the app in Applications →
Open → Open once.

Prefer the browser? Drop `rockdodge.gb` onto any web Game Boy emulator.

## Tweaking ideas
- The **Game constants** near the top set the rules: `GOAL_HI` (the goal is
  `GOAL_HI` × 100 points, so `$02` = 200 — also update the `TxtGoal` title text), `START_LIVES`, `MAX_SPEED`,
  `SPEEDUP_EVERY`, `SPECIALS_AT`. Point values are in `DodgePoints`, and the gem's
  5 points are in `CheckCollision`.
- The art is in the `Tiles` section at the bottom — each `` dw `00333300 `` line is
  one row of 8 pixels, using color slots 0–3. The actual colors live in the `Palettes` section (`rgb red, green, blue`, each 0–31) — change those to recolor anything.
- The song is in the `Music data` section: `MusicMelody`, `MusicBass` and
  `MusicDrums` are lists of `note, length` pairs (length in frames, 60 = 1 second;
  note 0 = rest; drums: 1 = snare, 2 = hi-hat). Note numbers count semitones up
  from C2 = 1, so A4 = 34, C5 = 37, E5 = 41. Keep all three tracks the same total
  length so they stay in sync.
- Sound effects are the `Play...Sfx` routines (score, gem, speed-up, pause, start,
  crash). The win fanfare is `WinMelody` / `WinBass` / `WinDrums`.
- The mountain outline is the 16 "mountain" tiles; edit them to draw a different
  skyline (a city, waves, etc.) and it will scroll the same way.
