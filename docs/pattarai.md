# Pattarai, the workshop

**தமிழ்:** [pattarai.ta.md](pattarai.ta.md)

Pattarai (பட்டறை, "workshop" or "forge") is where a Pulli game is made. It
opens in a web browser on your own computer and works on the game's folder
directly: the code, the pictures, the maps and the sounds. Everything it
saves is a file `pulli pack` already reads, so a game made in Pattarai is
packed, run and shared like any other, and its files can still be opened
in a paint program, in Tiled or in a text editor.

Its tools, one tab each:

| Tool | For | Makes |
|---|---|---|
| **Vidhi** (விதி, "rule") | the code | `*.lua` |
| **Kolam** (கோலம்) | sprites | `sprites.png` and other sprite sheets |
| **Ooru** (ஊர், "town") | maps | Tiled maps, `*.tmx`, and their tile flags in `sprites.tsx` |
| **Thirai** (திரை, "curtain" or "screen") | backdrops | 320 × 240 pictures, `*.png` |
| **Oli** (ஒலி, "sound") | sound effects | `sfx/*.wav` |
| **Isai** (இசை, "music") | music | `music/*.wav` |

A **Project** tab measures the whole game against the platform's limits,
and **Run game** plays it in the emulator.

## Starting it

From the repository's folder, with Python 3 (nothing else to install):

```bash
python3 tools/pulli.py edit mygame
```

`mygame` is the game's folder; `python3 tools/pulli.py new mygame` makes
one. Pattarai prints an address and, on a computer with a desktop, opens
it in the browser:

```
Pattarai is editing /home/you/mygame
open http://127.0.0.1:8765/#AbC123...
(Ctrl+C to stop)
```

The part after `#` is a key made fresh each time: the page needs it to
reach the files, so open the whole address. Ctrl+C in the terminal stops
Pattarai.

On a computer without a desktop, such as a Raspberry Pi used over SSH,
give a port and carry it to the computer you are sitting at:

```bash
python3 tools/pulli.py edit mygame 8765        # on the Pi
ssh -L 8765:127.0.0.1:8765 you@the-pi          # on your computer
```

then open the printed address on your computer.

Pattarai answers only on this computer (`127.0.0.1`), only to a page that
has the key, and only ever writes code, pictures, maps, tilesets, sounds,
songs and palettes inside the game's folder.

**Run game** and Vidhi's **Check** need the emulator built (see the
README's "Build and test"); the tools themselves do not.

## How the files reach the game

| In the game's folder | In the game |
|---|---|
| `main.lua`, `enemies.lua` ... | `require("enemies")` |
| `sprites.png` | `spr(n)`, counting 8 × 8 cells left to right, top to bottom |
| `actors.png` | `sheet.load("actors.kolam")` |
| `hall.tmx` | `map.load("hall.ooru")`, then `map.draw(0)` |
| `bg_forest.png` (320 × 240) | `backdrop("bg_forest.kolam")`, then `cls()` each frame |
| `sfx/00-jump.wav`, `sfx/01-coin.wav` | `sfx(0)`, `sfx(1)`: numbered in order of file name |
| `music/00-title.wav` | `music(0)` |

Oli and Isai also keep their settings beside each sound, as
`sfx/<name>.json` and `music/<name>.json`, so it can be opened and changed
again. `pack` leaves these out of the package.

A number at the front of a sound's name keeps the order, and so its
number, when more are added. Vidhi shows the number of every sound.

## Vidhi: the code

The game's Lua, coloured, with line numbers. Beside it are the game's
assets, and a click puts one into the code as the call that uses it:

- **Sprites:** click a sprite for `spr(n, x, y)`; drag across cells for a
  bigger one, `spr(n, x, y, 2, 2)`.
- **Sounds** and **Music:** each with a ▶ to hear it, its number, and how
  it will play: mono or stereo, its rate, its length and its size once
  packed. A sound can be put in on a channel of its own, `sfx(n, 0)`.
- **Maps:** `map.load("name.ooru")`.
- **Backdrops:** `backdrop("name.kolam")`.

Put the cursor on `spr(12, ...)`, `sfx(3)`, `music(1)`, `map.load(...)` or
`backdrop(...)` and the panel shows what it names: the sprite drawn, the
sound with a button to hear it, or that nothing has that number.

While typing, two letters (or Ctrl+Space) offer Pulli's functions, the
callbacks and the file's own names; Enter or Tab takes one. Inside a call,
the line under the code shows its arguments, the one being typed in bold.
Ctrl+F finds and replaces.

**✓ Check** saves, runs the game for two seconds with no window and lists
any error; click one to go to its line.

## Kolam: sprites

Draws on a sprite sheet in the game's 64 colours. Colour 0 is see-through.

- Work on a sprite of 8, 16, 32 or 64 pixels square; the sheet beside it
  shows where it is and which `spr(n)` it is. Arrow keys move to the next.
- Pen, fill, line, box, pick and erase; **Move** slides the sprite's
  pixels inside it. Flip, turn, copy, paste and clear work on the sprite.
- **Mirror** draws on both sides at once, left-right, up-down or both.
- **Animation** plays the sprite and the ones after it, as many frames
  and as fast as you ask. **Onion skin** shows the frame before, faintly.
- Keys: P pen, F fill, L line, R box, K pick, E erase, M move, Ctrl+Z
  undo, Ctrl+S save.

A sheet holds at most 128 KB of pixels (512 × 256), with sides that are
multiples of 8. Pictures made elsewhere open too; pixels not in the 64
colours take the nearest one.

## Ooru: maps

Paints Tiled maps with the sprite sheet's tiles: tile `n` is `spr(n)`, and
tile 0 is empty. A map saved here keeps everything else Tiled put in it.

- Two layers, 0 behind and 1 in front, each can be hidden.
- Paint, box (fill a rectangle), fill, erase and pick; flip tiles left-right
  (X) or up-down (Y). Drag across the tiles to paint with a block of them.
- **Copy** drags a rectangle of the map, a house or a room, and it becomes
  the brush, to paint again elsewhere.
- **Flags:** the tile in hand's eight flags, bit 0 being solid. They are
  kept in the tileset (`sprites.tsx`) and read by the game with
  `map.flags(tile)`. **Show flags** tints solid tiles red on the map.
- The frame on the map is one screen, 40 × 30 tiles.

The tiles are the picture open in Kolam. A map holds at most 32,768 tiles
over its layers.

## Thirai: backdrops

Whole-screen pictures, exactly 320 × 240, that `backdrop(name)` sets and
`cls()` starts each frame from: a still background for the cost of a copy.

- Pen (1 to 8 pixels), fill, line, box, filled box and pick.
- **Gradient:** drag from the colour to the second colour (right-click a
  colour to choose the second): a sky in one stroke. With **dither**, the
  shades between come out as a fine mix of the two.
- **Import picture** brings in a picture from your computer, scaled to
  cover the screen, cropped, and put in the game's colours.
- **Map over it** draws one of the game's maps on top, as the game would,
  to see the two together.

## Oli: sound effects

Start from a kind of sound and shape it, hearing each change:

- **Start from:** jump, coin, hit, explosion, laser, powerup, blip, hurt,
  tabla or bell. Click again for a variation; **More like this** changes
  every setting a little.
- Nineteen settings: the wave (square, saw, triangle, sine, noise or a
  struck tabla), how it rises, holds and fades, its pitch and slide, a
  jump in pitch, vibrato, the square's width, repeats, filters, bit-crush
  and volume.
- **Save** writes `sfx/<name>.wav`, mono at 22,050 samples a second, and
  says which `sfx(n)` plays it.

**Edit a WAV** opens any sound in `sfx/` or `music/`: drag across the wave
to choose a part, then trim to it, fade it in or out, normalise it to 90%,
make it quieter, reverse it or make it mono.

The console has 8 sound channels, 0 to 7, with music on top; sounds add
up and the total is clipped, so leave headroom.

## Isai: music

Music written as text, one line for each part, in a western scale or a
Carnatic raga, played by a synthesised band.

- **New Carnatic:** a raga (the 72 melakartas and common janya ragas), Sa,
  a tala (Adi, Rupaka, Misra Chapu...), tanpura drone, mridangam, thavil
  or kanjira; nadaswaram, venu, veena, harmonium and violin.
- **New western:** a key and scale, a time signature, piano, strings,
  flute, bass and a drum kit.
- **New chiptune:** square, pulse, triangle and noise voices with noise
  drums, as old consoles had, in a small mono WAV.
- **Example songs:** Für Elise in seven arrangements (piano, expressive
  piano, violin with gamakas, a band, chiptune, Keeravani with a konnakol
  part, and a tour of every instrument) and a Bilahari line. Opening one
  starts an unsaved copy; Save puts it in the game's music folder.

A part is written one note a step. In a new Carnatic song, as lines are
written by hand, a capital is two aksharas and a small letter one, and a
dot above or below a swara moves it an octave; **capitals long** switches
this off (the parts are rewritten to sound the same), and songs made
before it read every letter as one step:

```
S , r G P D Ṡ N D |                 as written by hand: capitals long, small short
s , r g m ; p | d. n. s' -          sargam: the raga's own swaras
R1 G3 M2                            a swara from outside the raga
C4 , E G Bb3 -                      western notes, with or without an octave
E' D'# E' B D' C'                   ' above the song's octave, . below
do re mi fa so , la ti do' -        movable do: do is the key note
do re me fa so le te do'            ... a minor scale, do-based
G~  P/  D\                          shake (kampita), slide up into, slide down into
S{0,4,7}                            an arpeggio: the note, a third, a fifth
P!3                                 a note at a third of the volume (!1 to !9)
```

`,` holds a note one step more, `;` two, `-` rests, `|` is a bar line,
`'` an octave up, `.` down.

Western parts can also be written in solfège. **Movable do** is the
default: do is the song's key note, as Sa is in a raga, so a tune keeps its
shape in any key; di, ri, fi, si and li raise a note a step, and ra, me,
se, le and te lower one (do-based minor: `do re me fa so le te`). **Fixed
do**, chosen under **note names**, is the French and Italian way: do is
always C and si is B, with `#`, `b` and an octave number. Letters work in
every song. Changing **note names** rewrites the parts to sound the same,
and notes are spelled from the key, as a musician writes them: B♭ in G
major's minor third, not A♯.

The **roll** under the parts shows the part in hand: click to place a note,
drag right to hold it, click a note to remove it. The scale's keys play
each note.

**Drums.** A song's kit (mridangam, thavil, kanjira, a drum kit or chip
drums) plays a pattern on its own, following the tala or time: **drum
pattern: automatic**. For a beat of your own, **+ Drum part** writes that
pattern out as a part to change, and sets **drum pattern: my own**, so only
the drum parts play. A drum part is written one stroke a step, in konnakol
or kit names, and the roll shows a lane for each kind of stroke:

```
thom ki tha ki | dhi ki tha ki      konnakol: deep, light, main, ringing
kick hat snare hat kick+hat         a kit: two strokes at once with +
tha ki ta ka!5 - ;                  a quieter stroke (!1 to !9), rests
```

A song can loop from a cycle after an intro. **Make WAV** writes
`music/<name>.wav`, stereo or mono, at 8,000 to 44,100 samples a second;
its size is shown as you choose.

The song's `.json` is the source; the WAV is made from it. Isai does its
own sums (no `Math.sin` or `**`), so a song makes the same WAV, byte for
byte, in every browser and in Node. Each WAV made notes in the song which
engine made it and the WAV's and the song's SHA-256; the header says
whether the WAV is up to date. **Make all WAVs** makes every song's WAV
that is missing or out of date, and so does Node without a browser:

```
node tools/pattarai/make-wavs.mjs examples/mygame
node tools/pattarai/make-wavs.mjs examples/mygame --all
```

`pulli pack` refuses a game whose song has no WAV (`music(n)` counts the
WAV files), and notes one that is out of date.

## Project

**Measure** packs the game as `pulli pack` does and checks it against the
spec: the package against 64 MB and 1,024 entries, each part against the
6 MB a game holds in memory at once, what is read as it starts, and the
Pico 2 board's 4 MB of flash. Bars show what takes the most room.

## Running the game

**▶ Run game** packs the game and plays it in the emulator's window; ■
closes it. With **restart on save** ticked it starts again a moment after
each save, so a change shows at once. The game starts from the beginning
each time: this is not hot reload.

## In Tamil

The **தமிழ்** button puts Pattarai's own words in Tamil. Code, file names
and swaras stay as they are written.

## Not yet

- Hot reload that keeps the game's state.
- Spawn points and other objects on a map: `pack` takes only Tiled's tile
  layers.
- The status line and help text in Tamil.
