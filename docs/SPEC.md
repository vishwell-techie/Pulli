# Pulli Platform Specification — v0.1 (DRAFT, for review)

Status: **§8 questions resolved and locked** (8x8 cells, 320x240 locked,
64-colour palette, named Pulli). Architecture revised per ADR-001 (GPU
coprocessor) and ADR-002 (audio). Remainder awaiting approval.
Revised October 2026 while the runtime was first built and tested: §10 lists
what was added or changed. All of it was approved by 18 October 2026; a new
change goes there until it is approved.
This document is the contract between the runtime, the SDK, and the hardware.
Everything else in the project is downstream of it. The ADR numbers it cites
are decision records kept outside this repository.

---

## 0. Design rules

These constraints hold for the whole design. A feature that violates one of
them does not ship.

1. **Two chips, one part number: RP2350B** (QFN-80, 48 GPIO, A4 stepping or
   later) as both CPU and GPU. See ADR-001 — the coprocessor exists to afford a
   parallel display bus and to move 153.6 KB of framebuffer off the CPU, not
   to make rasterizing faster.
2. **The emulator is the platform.** Hardware is one backend among several.
   A game must run bit-identically on desktop and device.
3. **Fixed memory.** No dynamic growth at runtime. Every buffer is sized at
   build time and declared in the manifest.
4. **No allocation in the hot loop.** The Lua GC must never be the reason a
   frame is missed.
5. **Lua only.** No native modules in games, ever. Portability and safety.
6. **Spec first, then two implementations.** Every API is defined here,
   implemented in the host runtime, and cross-checked against a reference
   renderer before it goes on hardware.

---

## 1. System model

| Property | Value | Rationale |
|---|---|---|
| Logical resolution | **320 x 240 (locked, never changes)** | Third-party games depend on it from here on |
| Framebuffer format | 8-bit indexed | 76,800 B/buffer vs 153,600 for RGB565 |
| Palette | **64 entries, RGB565 (locked)** | 32 hues + a shadow ramp 32 apart, so `pal(c,c+32)` darkens anything |
| Buffers | 2 (double-buffered) | 153,600 B total |
| Target frame rate | **60 Hz logic and full-frame redraw** | 8080 parallel bus: 5.1 ms/frame vs 19.7 ms over SPI (ADR-001) |
| Sprite budget | 128 sprites/frame @ 16x16 | Soft limit; profiler warns past it |
| Display interface | ST7789 8080 8-bit parallel, driven by GPU via PIO | The whole reason the coprocessor pays for itself |
| CPU<->GPU link | 8-bit parallel + CLK over PIO, DMA both ends, ~25-40 MB/s | Commands only, never pixels (ADR-001) |
| MCUs | 2x RP2350B (48 GPIO each), A4+ | Pin budget is full on the CPU, 8 spare on the GPU |
| CPU chip storage | 16 MB QSPI flash; 8 MB QSPI PSRAM on the same bus | Flash: firmware and the launcher. PSRAM: the game being played (§2, "Size, and the parts in memory") |
| GPU chip storage | 4 MB QSPI flash | Its own firmware only; sprite sheets and maps arrive over the link |
| Game package | **up to 64 MB, of which at most 6 MB is in memory at once** | Read from the SD card or a cartridge into PSRAM as the game uses it (§2) |
| Cartridge slot | Quad-SPI flash read by PIO; saves in the last 512 KB of that flash | A cartridge is read like the SD card, not in place (§2, "Cartridges") |
| Connector | USB-C, 24-pin receptacle, 5 V, no PD, SBU1/SBU2 routed to GPIO | Charging, flashing, Pulli Link; SBU reserved for a future link cable (ADR-008) |
| Tile layers | 2 scrolling + 1 sprite + 1 UI | |
| Audio | **8 channels, 44.1 kHz stereo, host and device identical** | Core 1 is free now the display moved off-CPU; costs ~6% of one core (ADR-002) |
| Input | 12 buttons: dpad, A B X Y, L R, START SELECT | |
| Lua | 5.4, with 32-bit integers and 32-bit floats; one pinned build for host and device | The RP2350's FPU is single precision; see §4 |

### Memory budget (RP2350, 520 KB SRAM)

**CPU chip (RP2350 #1, 520 KB)**

| Region | Size | Notes |
|---|---:|---|
| Lua VM heap | 256 KB | Raised from 192 KB — framebuffers moved to the GPU |
| Asset staging / SD streaming | 64 KB | |
| Command ring buffer (double) | 16 KB | |
| Audio buffers + ADPCM state | 32 KB | 44.1 kHz stereo |
| Game data, engine, stack, OS | ~96 KB | |
| **Total** | **~464 KB of 520 KB** | **~56 KB headroom** |

Outside its SRAM the CPU chip has 8 MB of PSRAM: 6 MB holds the parts of
the game's package in use (§2), and 2 MB is the system's.

**GPU chip (RP2350 #2, 520 KB)**

| Region | Size | Notes |
|---|---:|---|
| Framebuffers (2x indexed 320x240) | 153.6 KB | |
| Sprite atlas (resident) | 128 KB | |
| Tilemap working set | 64 KB | |
| Scanout strip buffers | 8 KB | index -> RGB565, DMA'd to panel |
| Command ring, code, stack | ~40 KB | |
| **Total** | **~394 KB of 520 KB** | **~126 KB headroom** |

Splitting across two chips is what turned "zero headroom" into "126 KB
spare on the tighter side". The index-to-RGB565 conversion still has to
happen, but it now happens on a chip with nothing else to do, overlapped
with DMA to the panel. Measured on a Pico 2 at 150 MHz, converting a whole
frame takes about 5.1 ms; overlapping it with DMA to a real panel is still
to be measured.

---

## 2. Game package format (`.pulli`)

A `.pulli` is a flat, uncompressed archive. Deliberately *not* ZIP: no
zlib on the MCU. A package can be read in parts, so a 64 MB cartridge
starts at once: only its **front** (header, entry table and block hashes)
is read and checked when it is opened, and each part of the payload when
the game first uses it.

```
offset  size  field
0       4     magic "PULI"
4       1     format version (u8), 2
5       1     flags (u8): 0x01 encrypted, 0x02 signed, 0x04 dev build
6       2     entry count N (u16 LE)
8       4     total size (u32 LE)
12      4     crc32 of the rest of the front, bytes 16 to P (u32 LE)
16      4     payload start P (u32 LE), a multiple of 4
20      N*40  entry table
20+N*40 B*32  block hashes: the SHA-256 of each 64 KB block of the payload,
              B = (total size - P) / 65536, rounded up; the last block may
              be shorter
P       ...   payload (each entry 4-byte aligned)
total   ...   the seal: licence and signature (see below)

entry (40 bytes):
0       32    name, NUL-padded ASCII
32      4     offset from file start (u32 LE), at P or after
36      4     length (u32 LE)
```

A package holds at most 1024 entries and is at most 64 MB. Entry names are
1 to 32 printable ASCII characters with no path separators; a 32-character
name has no terminating NUL. The checksum covers the front; every block of
the payload has its hash in the front, and a reader checks a block against
it before using any byte of it (once, for a package mapped in place;
every time it is read, otherwise). A damaged block stops the game when it
is used, with an error naming the part. The seal comes after `total size`
and is covered by none of these. A reader must check every offset and
length before using it, and must accept a file that is longer than the
package and its seal (a cartridge holds them at the start of a larger flash
region).

Required entries: `manifest.lua`, `main.lua`.
Conventional: `sprites.kolam`, `map.ooru`, `sfx.oli`, `music.isai`, `icon.kolam`,
`palette.pal`.
The asset extensions follow the tools that make them: Kolam
for sprites, Ooru for maps, Oli for sound effects, Isai for music.

### Size, and the parts in memory

A package may be up to **64 MB**. At most **6 MB** of it is held in memory
at once, the game's **active set**; the rest stays on the SD card or the
cartridge until the game needs it. This holds on every machine, the
emulator included, so a game that fits on a desktop fits on a console.

- A part of the package is read into the active set the first time the game
  uses it: a Lua file on `require`, a map on `map.load`, a sprite sheet on
  `sheet.load`, a sound the first time `sfx` or `music` plays it. A sound
  bank's table is read when the game starts; its sounds are read one at a
  time.
- `preload` (§3, "Loading") reads parts ahead of time, behind a loading
  screen, so nothing is read in the middle of play.
- Some parts are used where they lie and stay in the active set while in
  use: the sprite sheet in use, the map in use (its cells are copied into
  the engine, its tile flags read where they lie), the sound banks' tables
  and the sounds playing. Others need not stay: a Lua file, once compiled
  into the Lua heap, and a part `preload` read ahead.
- When the active set is full, the parts least recently used that are not
  in use are let go, and read again if wanted. A part that cannot fit even
  then stops the game with an error naming it, as running out of Lua memory
  does.
- Reading takes time, a fraction of a second for a large sound, but never
  changes what the game computes: the game stays deterministic (§4).

The emulator reads its package from disk in parts, as a console reads its
SD card, so the 6 MB is counted the same way there. A port may instead hold
the whole package in memory (flash read in place); the active set is
counted alike, and the game behaves the same.

### Cartridges

A cartridge holds one game in flash memory: the package and its seal at
offset 0 (see the seal, below), and the game's save data (§3, "Save data")
in the last 512 KB. The flash is sized to the game; a package may take all
of it but the save area, up to 64 MB. The console reads the flash over
quad-SPI like the SD card, into the active set; nothing on the cartridge is
run in place.

- **The save area** is written in turn, a slot after the last one used:
  each slot holds a whole save (at most `save_size`, so at least seven
  slots of whole 4 KB sectors), a number counting up and a checksum, and
  its header is written last. The console reads the
  newest slot whose checksum holds, so a cartridge pulled out or a battery
  going flat while a save is written loses only that save, never the one
  before. Writing in turn spreads the wear over the area: a 64 KB save
  written every 10 seconds, the most the rules allow, lasts hundreds of
  thousands of saves, far beyond a lifetime of play.
- Flash cannot be read while part of it is being erased, which takes up to
  about half a second. The console does not read the package while it
  writes a save, and holds a save until no part of the package is loading.

- A cartridge pulled out while its game runs pauses the game until it is
  back; the parts already in memory are not lost, and no save is written
  while it is out.
- The cartridge's contacts are 3.3 V, ground, the quad-SPI bus (clock,
  select, four data lines), an I2C pair kept for a chip on the cartridge,
  and a detect contact that breaks first when it is pulled.

### The seal: licence and signature

Every package is followed by a seal, starting at offset `total size`. It
says how the package is licensed and signed; header flags 0x02 and 0x04 are
reserved and unused.

```
offset  size  field
0       4     magic "SEAL"
4       1     seal version (u8), 1
5       1     licence kind (u8)
6       1     signature kind (u8)
7       1     reserved, 0
8       2     licence length L (u16 LE)
10      2     signature length S (u16 LE)
12      L     licence
12+L    S     signature
```

The signature is made over the package's front, bytes 0 to `P`; as the
front holds the hash of every block, it covers the whole package. Because
the seal lies outside the package's size and checksum, a licence or a
signature can be replaced without changing one byte of the package: the
store keeps one build of a game and attaches a seal per purchase.

| Kind | Licence | Signature |
|---|---|---|
| 0, developer | empty; the game runs on any device | the SHA-256 of the front, 32 bytes |
| 1 and up | reserved for the store | reserved for the store |

Every package a developer builds gets the developer seal automatically. A
developer signature catches a damaged or altered file; it proves nothing
about who made the package, since anyone can compute it. A runtime refuses
a package with no seal, with a signature that does not match, or with a
kind it does not know.

Lua sources are stored as **precompiled bytecode** (`luac -s`) in release
builds and as plain source in dev builds. The loader accepts either.
*Not yet: until the store exists, packages carry Lua source only and the
runtime refuses bytecode. Lua does not verify bytecode, so accepting it from
a package means trusting whoever built the package.*

### sprites.kolam (draft)

```
offset  size  field
0       4     magic "KLM1"
4       2     width in pixels (u16 LE), a multiple of 8
6       2     height in pixels (u16 LE), a multiple of 8
8       w*h   pixels, 8-bit palette indices, row by row
```

At most 128 KB of pixels (§1). On one chip the pixels are used in place,
never copied; the two-chip console sends them to the GPU chip once, when
the sheet comes into use.
`spr(n)` counts 8x8 cells left to right, top to bottom. A package may hold
several sheets; `sprites.kolam` is the one in use when the game starts, and
`sheet.load` (§3, "Loading") changes it.

`pulli pack` turns every `.png` in a game's folder into a `.kolam` of the
same name, so a game keeps `sprites.png` and never handles the format.
A pixel less than half opaque becomes colour 0, which sprites treat as
see-through. Any other pixel becomes the nearest of colours 1 to 63, so
solid black is colour 32 and stays visible. `pulli palette` writes the 64
colours as a `.gpl`, `.hex` or `.png` for a paint program; a picture drawn
with them imports unchanged, and `pack` says so when colours had to move.
PNG files of any colour type and depth are read, except interlaced ones.

### map.ooru (draft)

```
offset  size     field
0       4        magic "ORU1"
4       2        width in tiles (u16 LE)
6       2        height in tiles
8       1        layers: 1 or 2
9       1        reserved, 0
10      2        count F of tile flags, at most 16384
12      2*w*h*L  cells (u16 LE): layer 0 row by row, then layer 1
...     F        flags: one byte for each tile number from 0 to F-1
```

A cell holds a tile number in its low 14 bits; bit 15 turns the tile over
left to right and bit 14 top to bottom. Tile `n` is drawn as sprite `n`
from the sprite sheet, and tile 0 is empty, so maps never draw the sheet's
first cell. A map holds at most 32,768 cells over all its layers (64 KB,
§1). A file whose length is not exactly what its header implies stops the
game from starting. A package may hold several maps; `map.ooru` is the one
loaded at the start.

`pulli pack` turns every Tiled `.tmx` map in a game's folder into a
`.ooru` of the same name. The map must be orthogonal, not infinite, with
8x8 tiles from a single tileset, which is the game's sprite sheet. Its
first two tile layers become layers 0 and 1. Tiles flipped in Tiled stay
flipped; rotated tiles are refused. A tile's flags come from two custom
properties on the tileset's tiles: `flags`, a number from 0 to 255, and
`solid`, a tick box that sets bit 0. Object and image layers are not
imported.

### palette.pal (draft)

A game's own 64 colours, replacing the built-in palette (§8.3) for that
game: the magic `"PAL1"` then 64 colours of 3 bytes each, red, green and
blue, 8 bits each; 196 bytes in all. The runtime turns each into RGB565, as
for the built-in palette. Any other length or magic stops the game from
starting. `pulli pack` builds it from a `palette.hex` (one `rrggbb` a line)
or `palette.gpl` (GIMP, Aseprite and Krita's format) in the game's folder,
or takes a ready-made `palette.pal` as it is,
and then matches the game's PNG pictures to those colours instead of the
built-in ones. The conventions of §8.3, such as the shadow ramp 32 apart,
are the game's to keep or not.

### sfx.oli and music.isai (draft)

Two sound banks with one layout: `sfx.oli` holds the sounds `sfx(n)`
plays, `music.isai` the tracks `music(n)` plays. Numbers are little-endian.

```
offset  size  field
0       4     magic: "OLI1" for sfx.oli, "ISA1" for music.isai
4       2     count of sounds, at most 256
6       2     reserved, 0
8       28*N  one entry per sound:
                +0   4  offset of its data from the start of the bank
                +4   4  size of its data in bytes
                +8   4  length in frames (a frame is one sample per channel)
                +12  4  loop start, a frame number below the length
                +16  2  sample rate, 4000 to 48000 Hz
                +18  1  channels: 1 or 2
                +19  1  encoding: 0 exact, 1 squeezed
                +20  8  loop state, for squeezed sounds (below)
...           data, each sound starting on a multiple of 4
```

- **Exact** (encoding 0) is signed 16-bit samples, left before right.
- **Squeezed** (encoding 1) is IMA ADPCM, 4 bits a sample: a quarter the
  size, at a small cost in quality. The codes run in one unbroken stream
  from a decoder that starts at value 0, step index 0. Sample `k`, counting
  left and right separately, is the low half of byte `k / 2` when `k` is
  even and the high half when odd.
- **Loop state** lets a player jump back to the loop start of a squeezed
  sound without decoding from the beginning: for the left channel and then
  the right, the decoder's value (signed 16 bits), its step index (one byte,
  at most 88) and a zero byte, as they stand just before the loop start.
- A bank that breaks any of these rules stops the game from starting.

`pulli pack` builds both banks from a game's `sfx/` and `music/` folders:
the `.wav` files in each, numbered from 0 in order of file name. Sound
effects are stored exact and music squeezed. A loop point marked in a WAV
file is kept; otherwise music loops from its start. Mono or stereo PCM WAV,
8 to 32 bit, 4000 to 48000 Hz.

### manifest.lua

```lua
return {
  id          = "com.yourname.stardash",  -- reverse-DNS, unique
  title       = "Stardash",
  author      = "Your Name",
  version     = "1.0.0",
  spec        = 1,                        -- Pulli spec version required
  save_target = "sd",                     -- "sd" | "cart" | "none"
  save_size   = 4096,                     -- bytes, max 65536
  save_mode   = "exit",                   -- "exit" | "auto": when saves are written (§3)
  save_interval = 60,                     -- seconds between automatic writes, 10 to 3600
  lua_heap    = 192,                      -- KB requested, max 256 (§1)
  icon        = "icon.kolam",
}
```

The launcher reads only the manifest — never executes `main.lua` — to build
the game list. Manifest is evaluated in a sandbox with no I/O: no libraries
at all, 64 KB of memory and a limit on how long it may run.

`id`, `title` and `spec` are required. `id` may use letters, digits, `.`,
`_` and `-`, and may not start with `.`; it names the game's save data.
Defaults: `save_target = "none"`, `save_size = 4096`, `save_mode = "exit"`,
`save_interval = 60`, `lua_heap = 256`.
A game whose `spec` is newer than the runtime is refused. Unknown fields
are ignored.

---

## 3. Lua API — v0.1

### Lifecycle

```lua
function init()      end  -- once, after assets mount
function update(dt)  end  -- 60 Hz, dt in seconds: always 1/60 (§4)
function draw()      end  -- 60 Hz, after update
```

If `update` or `draw` overruns its budget the engine drops the *draw*, never
the *update*. Logic stays deterministic; visuals degrade.

### Graphics

```lua
cls(c)                             -- clear to palette index c (default 0); cls() starts from the backdrop, if set
pset(x, y, c)   pget(x, y)
line(x0,y0,x1,y1,c)
rect(x,y,w,h,c) rectfill(x,y,w,h,c)
circ(x,y,r,c)   circfill(x,y,r,c)
shade(c, lights, edge)             -- darkness with lights cut out of it
spr(n, x, y, w, h, flip_x, flip_y) -- n = sprite index; w,h in 8px cells
sspr(sx,sy,sw,sh, dx,dy, dw,dh)    -- stretched blit
print(text, x, y, c)               -- UTF-8, English and Tamil; returns the x after it
text_size(text)                    -- width of the widest line and height of all, in pixels
font(size)                         -- "normal" or "small": the size Tamil is drawn at
buttons.a                          -- each button's icon, as a character to put in text
camera(x, y)                       -- world -> screen offset
clip(x, y, w, h)                   -- nil = reset
pal(a, b)                          -- remap palette index a -> b
palt(c, is_transparent)
fade(amount)                       -- 0..1, palette-level, free
palette(c, r, g, b)                -- give colour c new RGB; palette(c) reads it (§5)
```

**Arguments.** Every coordinate and size may be a float; it is rounded down
to a whole pixel and held to the range -32768..32767 (the range the GPU
command format carries, ADR-001). Colour indices wrap at 64, so `c` and
`c + 64` are the same colour; that holds for sprite pixels too. `pal()` and
`palt()` with no arguments restore the defaults. `fade` sets a level and
does not accumulate: `fade(0.5)` every frame holds half brightness, and
`fade(0)` restores the picture. Shapes may cross the screen edge freely.

**Shade.** `shade(c, lights, edge)` paints colour `c` (default 0) on every
pixel of the clip rectangle that no light reaches. `lights` is a flat list
`{x1, y1, r1, x2, y2, r2, ...}` in drawing coordinates, each number taken
like any coordinate; a light covers exactly the pixels `circfill(x, y, r)`
would. Only the first 64 lights count, and anything but a table means no
lights. On each row the lights' spans are joined where they overlap or
touch; on the first and last `edge` pixels of each joined span (0 to 32,
default 0, and no more than half the span's width, rounded down), `c` goes
on the pixels whose `x + y` is even, in drawing coordinates, softening the
edge. It does in one call what a night scene would otherwise draw with
hundreds of `rectfill` and `pset` calls.

### Text

`print` draws UTF-8 text in two scripts, with the top of its first line at
the `y` given.

- **English** (ASCII 32 to 127) comes from the built-in 8x8 font: every
  character is 8 pixels wide and 8 tall.
- **Tamil** comes from the built-in Tamil font, which draws whole
  syllables: every consonant alone, with the pulli and with each vowel
  sign, every vowel, and ஸ்ரீ. Text is matched longest first, so a consonant
  and the sign after it are drawn as one glyph, already shaped: ெ, ே and ை
  before the letter, ொ, ோ and ௌ around it, ு and ூ joined to it. Each glyph
  has its own width and advance.
- **Two Tamil sizes.** `font("small")` switches `print` and `text_size` to
  the small Tamil font, and `font()` or `font("normal")` back; the size
  stays until changed, like `camera`. English and the icons do not change
  size. Any other size is an error.
- **Button icons.** Each button has an icon, a character in Unicode's
  private use area, U+E000 to U+E00B in the order `left right up down a b
  x y l r start select`. The table `buttons` holds them as strings,
  `buttons.a` and so on, so a game can write `print("Press " .. buttons.a)`
  in any language. An icon is 8 pixels tall and sits on the line like an
  English letter; `start` and `select` are 12 pixels wide, the others 8.
  The same icons are built into every Pulli, so every game shows the same
  buttons.
- A line holding any Tamil is as tall as the Tamil font in use (22 pixels
  at the normal size, 16 at the small, in each font's `! rows=` line), and
  English and icons on it are lowered to share the Tamil baseline. Any
  other line is 8 pixels tall.
- **Numbers follow the line.** Each Tamil font has its own digits 0 to 9,
  made at its size. On a line holding Tamil the digits come from the Tamil
  font in use, so a number is as large as the words around it; on any
  other line they are the 8x8 English digits. Only the digits change:
  other English characters on a Tamil line (`/`, `%`, `:` and so on) stay
  8x8. `\n` starts the next line
  below the last one, at the `x` given.
- A character neither font has, and a byte that does not begin a
  well-formed UTF-8 character, are drawn as `?`.
- `print` returns where the next character would have gone on the last
  line. `text_size(text)` returns, without drawing, the width of the widest
  line and the height of all the lines.

The fonts are `runtime/font.txt` (English and the icons),
`runtime/font_ta.txt` and `runtime/font_ta_small.txt`, plain text. The Tamil
fonts are made from Noto Sans Tamil Medium, at 17 and 14 pixels to the em,
by `tools/fontgen/ta_from_font.py`, and are under the SIL Open Font License
1.1 (`third_party/noto-sans-tamil/`). `tools/refgfx.py` lays text out the
same way, and the conformance tests hold the runtime to it.

### Map

```lua
map.load(name)                     -- load another map from the package (default "map.ooru")
map.size()                         -- width, height in tiles; 0, 0 with no map
map.draw(layer, sx, sy)            -- layer 0 = behind, 1 = in front; sx, sy optional
map.get(layer, cx, cy)             -- tile, flip_x, flip_y
map.set(layer, cx, cy, tile, flip_x, flip_y)
map.flags(tile)                    -- 8 collision/meta bits per tile
```

- A game with a `map.ooru` starts with it loaded. `map.load` replaces the
  loaded map, and is an error if the package has no map of that name.
- `map.draw` draws a layer with its top-left corner at `(-sx, -sy)`. Like
  every other drawing call it is moved by `camera()` and cut by `clip()`,
  so `camera(x, y)` followed by `map.draw(0)` scrolls the map and the
  sprites together, and a layer given a different `sx, sy` moves at its
  own speed. Only tiles that reach the screen are drawn.
- Tile 0 is empty. Tile `n` is sprite `n`, 8x8 pixels, and sprite
  transparency applies, so layer 1 shows layer 0 through its gaps.
- `map.set` changes the loaded map, not the package: loading the map again
  brings the original back. A tile number above 16383 is ignored.
- Outside the map, `map.get` gives 0 and `map.set` does nothing. With no
  map loaded every function is harmless.
- `map.flags` gives 0 for a tile that has no flags.

### Loading

```lua
sheet.load(name)                   -- use another sprite sheet from the package
preload(name, ...)                 -- read parts of the package into memory now
stat("active")                     -- KB of the package in memory
backdrop(name)                     -- a picture each frame starts from; backdrop() lets it go
```

- `sheet.load(name)` makes the `.kolam` called `name` the sheet that `spr`,
  `sspr` and `map.draw` draw from, and is an error if the package has none
  of that name. Sprites already drawn stay on the screen.
- `preload` reads the named parts into the active set (§2) and returns
  when they are there: entry names such as `"lake.ooru"` or `"lake.kolam"`,
  and `"sfx 12"` or `"music 3"` for one sound. It returns `true`, or `false`
  if a name is not in the package. Parts read this way may still be let go
  later if the active set fills up with others.
- `backdrop(name)` sets the `.kolam` called `name`, which must be exactly
  the screen's size, 320 x 240, as the backdrop: it is read once and kept
  in the active set while it is set (on a console with a graphics chip, it
  is sent there once). While a backdrop is set, `cls()` with no colour
  starts the frame from it instead of clearing: each pixel as it is, or
  through `pal()` if colours are swapped; like any `cls`, it ignores the
  camera and the clip. `cls(c)` still clears to `c`. `backdrop()` lets it
  go. A picture of another size, or one the package does not have, is an
  error naming it. A still background drawn this way costs a copy, not a
  sprite drawn pixel by pixel every frame.
- A game that never calls them works as it does today: everything it uses
  is read when first used.

### Input

```lua
btn(b)    -- held.  b = "left","right","up","down","a","b","x","y","l","r","start","select"
btnp(b)   -- pressed this frame (with repeat, except "start" and "select")
```

`btnp` is true on the frame a button goes down. If the button stays down it
is true again 24 frames later and every 6 frames after that, so holding a
direction scrolls a menu. `start` and `select` never repeat: they pause,
confirm and quit, where a second firing would undo the first.

### Audio

```lua
sfx(n, channel)          -- play sound n; channel optional, -1 = auto
music(n, fade_ms, loop)  -- play track n; fade_ms optional (0), loop optional (true)
music_stop(fade_ms)
music_pause(paused)      -- true (the default) holds the music still; false carries on
```

- There are 8 sound-effect channels, 0 to 7. A sound started on a channel
  replaces whatever was playing there. With no channel given the sound takes
  a free one, or else the channel whose sound started longest ago.
- `sfx(-1, channel)` silences that channel, and `sfx(-1)` all of them.
- Music is mixed on top of the 8 channels. `music` with a fade brings the
  new track in over `fade_ms` while the old one fades out over the same
  time; `music_stop` fades out and stops. A track loops from its loop point
  until stopped, or plays once when `loop` is false.
- `music_pause` holds the music, and any fade it is in the middle of, where
  it is; sound effects are not affected. `music_stop` and starting new music
  both end a pause. Pausing with no music playing does nothing.
- A sound or track number that does not exist does nothing, as does a
  channel above 7. A game with no sounds may call any of them freely.
- A sound starts in the frame that asked for it. The engine mixes exactly
  735 stereo samples per frame, 44.1 kHz, 16 bits.
- Sounds add up at full level and the total is clipped, so eight loud
  sounds at once distort: leave headroom in the source files.
- A sound recorded at another rate is brought to 44.1 kHz by straight-line
  interpolation between neighbouring samples.
- The mix is integer arithmetic throughout (§4): the same game makes the
  same samples on every machine.

### Save data

```lua
save(key, value)   -- value: number, string, boolean, or a table
load(key, default)
save_commit()      -- flush to storage now
```

Saves are a key-value blob capped at `save_size`. No filesystem access from
games — ever. This is what makes cartridge/SD parity trivial.

`save_target = "cart"` keeps a cartridge game's saves in the cartridge's
own flash, in its save area (§2, "Cartridges"), so they go wherever the
cartridge goes. The same game run from the SD card (a
developer's copy, say) keeps them on the SD card, as `"sd"` does. A game
does not see the difference.

Keys are 1 to 32 characters from letters, digits, `_`, `-` and `.`. `save`
returns `true`, or `false` if the key is bad, the value is of an unsupported
type, the store is full, or the game has no `save_target`. Saving `nil`
deletes the key. `load` returns the value with the type it was saved with.

A **table** may hold numbers, text, booleans and other tables, and its keys
may be numbers, text or booleans. Tables may be nested four deep. `save`
returns `false` for a table that holds a function or other unsupported
value or key, is nested deeper, or contains itself; the value kept is the
table's contents, and `load` returns a new table each time, so changing it
changes nothing until it is saved again. One saved value, a table included,
is at most 65535 bytes. A stored table that does not read back whole is
treated as never saved.

**When saves are written.** Save data is kept in memory while the game runs.
It is written to storage when the game ends and at the **checkpoints** the
game chooses by calling `save_commit()`, for instance on reaching a new
level or a save point. A crash or a flat battery loses what was saved since
the last of these. The manifest's `save_mode` can add automatic writes:

- `"exit"` (the default): only at the end of the game and at checkpoints.
- `"auto"`: also in the background. A change is written once
  `save_interval` seconds of game time have passed since the last write,
  automatic or at a checkpoint. `save_interval` is the game's choice, from
  **10** to 3600 seconds, and is 60 if the game says nothing; a value below
  10 stops the game from starting. A game that saves every frame therefore
  writes at most once in that time. A failed automatic write is not retried
  until the next interval.

Flash wears with every write, which is why the automatic interval has a
floor. `save_commit()` has none, because a checkpoint is the game's own
decision: call it at real checkpoints, not every frame.

### Link

Two consoles joined by a link cable can exchange short messages. This is
optional hardware: check `sys.has("link")` before building a mode around it.

```lua
link.status()   -- "off" (no link hardware), "waiting" or "connected"
link.side()     -- 1 or 2 while connected, otherwise nil
link.send(msg)  -- queue a string for the other console; true if accepted
link.recv()     -- the next message that arrived, or nil
```

- A message is a string of at most 64 bytes; `string.pack` and
  `string.unpack` are the way to put numbers in one. A game may send at
  most 8 messages per frame. `send` returns `false` beyond either limit, or
  when not connected.
- While connected, messages arrive whole, in the order sent, none lost. A
  message is never delivered in the frame it was sent; one frame later is
  the best case, and a game must not count on a particular delay.
- The two consoles are given different sides, 1 and 2, when they connect.
  That is all the link decides: a game uses it to agree who does what, for
  example side 1 running the match and side 2 following.
- The link carries bytes between two copies of the same game. It does not
  keep them in step; what to send, and what to do when the other side is
  late or gone, is the game's protocol. When the other console leaves,
  `status` returns to `"waiting"` and anything not yet received is dropped.
- Messages come from another console: treat them like any outside input
  and check their length and contents before using them.

The emulator links two host windows on one computer: start both with
`--link` and the same port number. `examples/pong` has a link mode built
this way. How the link is carried between real consoles is not part of this
contract.

### Fixed point

Games compute in floats by default. `fix` is an optional second kind of
number for a game that wants whole-number exactness: a 16.16 fixed-point
number is an ordinary Lua integer that counts 65536ths, so `fix.one` is
65536 and one and a half is 98304.

```lua
fix.one, fix.pi        -- 65536, 205887
fix.from(n)            -- a number as fixed point; an integer n means n whole units
fix.to(a)              -- fixed point as a float
fix.floor(a)           -- the whole part, as an integer, rounded down
fix.mul(a, b)   fix.div(a, b)   fix.sqrt(a)
fix.sin(a)      fix.cos(a)      fix.atan(y [, x])    -- angles in radians
```

- Add, subtract, negate and compare with Lua's own `+`, `-` and `<`.
  Multiply and divide need `fix.mul` and `fix.div`; `*` and `/` on two
  fixed-point numbers give the wrong scale.
- The range is -32768 to just under 32768, in steps of 1/65536. Everything
  wraps around at 32 bits, as Lua integers do; nothing clamps. `fix.from`
  gives 0 for infinity and not-a-number.
- `from`, `floor`, `mul`, `div` and `sqrt` round down (toward minus
  infinity). `sin`, `cos` and `atan` round to the nearest 65536th. `to`
  rounds to the nearest float.
- `fix.div` by zero and `fix.sqrt` of a negative number are errors.
- Every function except `from` takes integers only. A float that is not a
  whole number is refused, which catches a float passed by mistake.
- Results are the same bits on every machine, as for floats (§4).

**Uniformity rule.** A game uses the same kind of number for the same
calculation on every device. The engine never switches a game between
floats and fixed point, and a game must not choose between them by asking
what hardware it is on. Which one a calculation uses is decided when the
game is written.

### System

```lua
sys.has(cap)       -- "video","wifi","cart","rumble","link" -- hardware varies by variant
time()             -- seconds since the game started: stat("frame") / 60
stat("fps") stat("mem") stat("cpu") stat("frame")
dbg(...)           -- printf to host console / device serial; stripped in release
```

`stat("frame")` is the number of updates since the game began, and
`stat("mem")` the Lua memory in use, in KB. `stat("fps")` is the updates a
second over the last second, and `stat("cpu")` the percentage of the last
frame's 1/60 s that its update and draw used. These two come from a clock
that the port supplies, and are `nil` where it has none. They are for
finding out why a game is slow, not for the game to act on: they differ
from run to run, and a game that depends on them is no longer deterministic
(§4). Any other name gives `nil`.

### More than one Lua file

```lua
local enemies = require("enemies")   -- runs enemies.lua from the package
```

- `require(name)` runs `name.lua` from the game's package the first time it
  is asked for and returns what the file returned, or `true` if it returned
  nothing. Asking again returns the same value without running the file.
- A name is letters, digits and `_` only. Modules come from the package and
  nowhere else, as source text; `main` and `manifest` cannot be required.
- A missing module, a mistake in one, and two modules that require each
  other are errors that name the file.
- The file is passed its own name, as `...`.
- `unrequire(name)` forgets a module and returns `true` if it was loaded.
  Its memory is collected once nothing else holds what it returned, and
  the next `require(name)` runs the file again. A game split into levels or
  chapters can drop the ones it has left. A module cannot be forgotten
  while it is still loading.

### Batteries (Lua-level, shipped as SDK source, not engine)

Helpers written **in Lua** and kept in `sdk/`, so developers can read, fork
and replace them. Nothing here is privileged: each is an ordinary module
loaded with `require`, and each file documents itself at the top.

A game only has to require a helper. When the game is packed, `pulli pack`
reads its Lua files for `require("name")` and, for each name the game's
folder has no file for, puts the SDK's `name.lua` into the package; a
helper that requires another brings it along. The package is complete in
itself, and the runtime knows nothing of the SDK. A file in the game's
folder is always used in place of the SDK's, so a game changes a helper by
keeping its own copy (`pulli add <game> <helper>`). Requiring a name that
is in neither place is an error when packing. Only names written out in
the source are seen: a name worked out while the game runs must be a file
in the game's folder.

| Helper | For |
|---|---|
| `tween` | changing numbers smoothly over time, with easing |
| `camera_follow` | a camera that follows a target, with a dead zone, map bounds and shake |
| `inventory` | what the player carries: slots, stacks, and keeping it in the save data |
| `dialog` | a text box: typed-out text, wrapping, pages, and questions with answers |
| `quest` | what the player has been asked to do: steps, counts, and keeping it in the save data |
| `particles` | sparks, dust and smoke: a fixed pool of dots that fly, fall and fade |
| `input` | presses that fire once and never repeat, releases, and how long a button is held |
| `move` | moving a box through the map: stops flush at walls, slides along them, never passes through |
| `anim` | sprite animations by name, with frame rates and animations that play once |
| `scene` | a game's screens, each with its own update and draw, and screens pushed over others |
| `text` | centred, right-aligned, shadowed and outlined text; clocks, padded numbers, wrapping |
| `timer` | calls after a delay or at a steady beat, and cooldowns, all in game time |
| `menu` | a list to choose from, with scrolling, wrapping and a box |
| `pathfind` | the shortest way round the walls of the map, with a limit on the search |
| `store` | a table, tables inside it included, kept exactly in the save data |
| `transition` | fading or wiping to black and back between screens |
| `pool` | reusing objects instead of making new ones, so the garbage collector stays quiet |

---

## 3a. Capability rules (hardware variants)

One board design is populated differently per variant, so a game must never
assume hardware is present.

- Every capability is optional. Games must run correctly on the minimum
  configuration and treat the rest as enhancement.
- Missing hardware degrades silently: `rumble()` on a unit with no motor is a
  no-op, never an error.
- The emulator can simulate any configuration, so a variant can be tested
  without owning one.
- Future generations **add** capabilities and never remove them. That is what
  keeps old games running.

## 4. Determinism

`update(dt)` receives a fixed 1/60 on device and on host by default. Games
that use `dt` for integration still work; games that assume fixed step also
work. The host may one day offer a variable-step mode for debugging,
behind a flag; none exists yet.

Rationale: determinism gives us replay files, which give us automated
regression tests for the runtime — the only practical way to verify that
the desktop and device backends agree.

What the runtime does to make that true:

- **One number model everywhere.** Lua integers are 32-bit and wrap; Lua
  floats are 32-bit IEEE. The desktop does not use the system's Lua: host
  and firmware build the same pinned Lua source with the same settings.
- **No fused multiply-add.** `a*b+c` rounds twice on every CPU.
- **`math.random` starts from a fixed seed.** A game that wants a different
  sequence each run reseeds from player input timing.
- **String hashing uses a fixed seed**, so `pairs()` walks string keys in
  the same order on every run and machine. Order over table, function or
  userdata keys still depends on memory addresses: do not let game logic
  depend on it.

- **One maths library everywhere.** `math.sin`, `cos`, `tan`, `asin`,
  `acos`, `atan`, `exp`, `log` and the `^` operator are computed by the
  runtime itself, in integer arithmetic, and not by the C library. They
  return the same bits on every machine, and each result is within one unit
  in the last place of the true value. `math.fmod` and `%` on floats are
  computed by the runtime too, exactly: IEEE 754 defines the remainder
  exactly, but the C library the Pico SDK links does not always find it.
  `math.sqrt`, `//`, `math.floor` and `math.ceil` are left to the platform,
  because IEEE 754 defines their results exactly and every library checked
  gets them right; the runtime's self-check covers them.
- **A float unit is optional.** Games always compute in 32-bit IEEE floats.
  A chip with a float unit uses it; a chip without one does the same
  arithmetic in software and gets the same bits, only more slowly. A port
  never switches a game to a different kind of number, because that would
  change how the game behaves.
- **Sound is deterministic too.** The mixer is part of the runtime, works
  in integers and is driven by the frame count, never by a sound card's
  clock. A port receives finished samples and only has to play them.
- **Fixed point is a choice, not a fallback.** The `fix` functions (§3) are
  integer arithmetic and are equally exact everywhere. A game may use them,
  floats, or both, but the same way on every device.
- **A port proves it.** The runtime carries a self-check that runs these
  functions, plain float arithmetic and fixed point over a fixed set of
  inputs and compares a checksum of the results with a recorded value. A
  port is not conformant until it passes. The Pico 2 firmware passes.

Not yet covered: turning a number into text and text into a number
(`tostring`, `string.format`, `tonumber`, and decimal numbers written in
source) still goes through the C library. A game whose logic depends on the
exact digits may differ between desktop and device.

---

## 5. Coordinate & color conventions

- Origin top-left, +y down, integer pixel centers.
- Palette index 0 is transparent for sprites by default (`palt` overridable).
- The default 64-colour palette (§8.3) is built into the runtime. Games
  may supply their own 64 colours with a `palette.pal` (§2), and change
  any colour while running with `palette(c, r, g, b)`, red, green and blue
  from 0 to 255; `palette(c)` returns colour c's red, green and blue as they
  are kept (5 bits of red and blue, 6 of green, widened back to 0..255 by
  repeating their top bits); `palette()` puts the game's colours back.
  Colour numbers wrap at 64, and `fade` applies to the new colours as to the
  old. `tools/refgfx.py` models all of this and the tests hold the runtime to it.

---

## 6. Toolchain

```
pulli new <name>       scaffold a project
pulli run              build + launch in the host emulator, hot reload
pulli pack             produce <name>.pulli
pulli check            static checks: API misuse, budget overruns, GC churn
pulli flash            push to device over USB
```

`pack` takes every file in the game's folder except hidden ones (a name
starting with `.`), Tiled tilesets (`.tsx`, read through the maps that use
them), Markdown (`.md`), which is left for people to read, such as a
game's README, and files the operating system makes: any name with a `:`
in it (Windows adds a `<name>:Zone.Identifier` beside each downloaded file
copied into WSL), `Thumbs.db` and `desktop.ini`. A package with more
entries than it may hold is refused with the list of what was packed.

Today the CLI is `python3 tools/pulli.py`. `new`, `pack`, `list`, `unpack`
and `run` work, as do `palette` (write the palette for a paint program),
`add` (list the SDK helpers, or copy one into a game to change it) and
`cart` (a cartridge's flash as a file, which `pulli-headless --cart` runs
like a console runs the cartridge, saves included); `check`
runs the game with no window and reports errors and peak memory, without the
static checks yet; hot reload and `flash` do not exist yet.

---

## 7. Deliberate deviations from the earlier plan

| Earlier plan | Now | Why |
|---|---|---|
| RP2040 as GPU over SPI command stream | **Second RP2350 as GPU over PIO parallel** | Same idea, better part: 2x SRAM, one part number, shared source (ADR-001) |
| SPI display | **8080 8-bit parallel** | The actual unlock for 60 FPS; only affordable because a dedicated chip can spend the pins |
| RGB565 framebuffer | 8-bit indexed + palette | Halves RAM, enables free fades/flashes |
| 44.1 kHz stereo on device | **44.1 kHz stereo retained** | Core 1 is free once the display moves off-CPU (ADR-002) |
| `.pulli` = folder/zip | Flat XIP-friendly archive | No zlib on MCU; a package in memory is read in place |
| Cartridges in v1 | **Cartridge slot in the first generation** | Read like the SD card, over quad-SPI, into memory; saves in the cartridge's own flash (§2) |
| Package size set by memory | **64 MB package, 6 MB in memory at once** | Parts are read as the game uses them, so a big game needs no more memory (§2) |

---

## 8. Resolved decisions (locked)

1. **Sprite cell size: 8x8**, composed via `w,h` multipliers.
2. **Resolution: 320x240 logical, locked.** Not revisitable once third-party
   games exist.
3. **Palette: 64 entries.** 32 base hues + a shadow ramp at the same indices
   +32, so `pal(c, c+32)` darkens any sprite and dimming a scene is free.
4. **Name: Pulli** (புள்ளி, "dot").

---

## 9. Known risks in this spec

- **The parallel display write rate is unmeasured.** Everything about 60 FPS
  rests on ≥25 MB/s to the panel. If bring-up shows under 15 MB/s we fall
  back to dirty-rectangle updates — the architecture survives, the software
  gets more complex.
- **The PIO link is the new schedule risk.** Not technically hard, but
  inter-chip bring-up always takes longer than planned. Budget three weeks.
- **One frame of added input latency** from the CPU/GPU pipeline. Fine for
  RPGs; a `lowlatency` manifest flag is planned for twitch games, but is
  not part of v0.1.
- **Index-to-RGB565 conversion overlapped with the panel's DMA is
  unmeasured.** The conversion alone takes about 5.1 ms a frame on a Pico 2
  at 150 MHz.
- **Lua GC pauses.** Mitigation is stepped GC per frame plus object pooling in
  the SDK, but this is unproven at this scale on Cortex-M33.
- **Reading parts of a package mid-play.** A game that does not preload
  can pause for a fraction of a second when a large sound or map is first
  used. The emulator must imitate SD and cartridge read speeds so this
  shows up on a desktop.
- **Audio can still sound cheap at 44.1 kHz stereo.** ADR-002 settled the
  sample rate; what people hear is the analog stage and the speaker's back
  volume. Needs a listening test early, not late.

---

## 10. Changes in this revision (October 2026)

Made while building and testing the first runtime. Items 1 to 28 were
approved by 18 October 2026; later items await approval. Each is
implemented and covered by `tests/`; none is frozen until spec 1.0.

1. **Names.** The platform is Pulli; the package is `.pulli` with magic
   `PULI`; asset entries are `.kolam`, `.ooru`, `.oli`, `.isai`.
2. **Lua number model** (§1, §4): 32-bit integers and floats, one pinned Lua
   build for host and device.
3. **Determinism rules** (§4): fixed random seed, fixed hash seed, no fused
   multiply-add.
4. **Argument conventions** (§3): fractions round down, coordinates are held
   to 16 bits, colour indices wrap at 64, `pal()`/`palt()` reset, `fade`
   sets a level instead of accumulating.
5. **Package limits** (§2): 64 entries (1024 since item 29), name rules, what the checksum
   covers, and the first asset format, `sprites.kolam`.
6. **Manifest rules** (§2): required fields, defaults, id characters, and
   `lua_heap` up to 256 KB to match the memory budget in §1.
7. **Save data** (§3): key rules, return values, typed values, and one blob
   per game as the only thing a backend stores.
8. **`btnp` repeat** (§3): the timing is now defined, and `start` and
   `select` are excluded from it.
9. **The seal** (§2): licence and signature follow the package instead of
   being entries inside it; `license.bin` and `signature.bin` are no longer
   reserved names. Developer builds carry a default licence and signature.
10. **Link API** (§3): `link.status`, `link.side`, `link.send`, `link.recv`,
   with their limits and delivery rules.
11. **Maths** (§4): the runtime's own `sin`, `cos`, `tan`, `asin`, `acos`,
   `atan`, `exp`, `log` and `^`, identical on every machine; software
   floats on a chip with no float unit; and the self-check a port must
   pass. This closes the gap §4 used to list.
12. **Fixed point** (§3): the `fix` functions for 16.16 numbers, their
   rounding and wrapping rules, and the uniformity rule: the same kind of
   number on every device.
13. **Audio** (§2, §3): the `sfx.oli` and `music.isai` bank format, how
   `pack` builds them from WAV files, 8 effect channels with music on top,
   `sfx(-1)` to silence, a third `loop` argument to `music`, and a mixer
   inside the runtime that produces 735 samples per frame.
14. **Pictures and maps** (§2, §3): PNG files become sprite sheets and
   Tiled maps become `map.ooru` when a game is packed; the `map.ooru`
   format, with 16-bit cells, flips and tile flags; `map.load`, `map.set`,
   `map.flags` and the new `map.size`; `map.get` also returns the flips;
   and `map.draw` now follows `camera()`, which it used to ignore.
15. **`require` and the SDK helpers** (§3): a game may be split over several
   Lua files loaded with `require`, from its own package only; the
   helpers in `sdk/` (§3, "Batteries"); and `pack` supplying the helpers a
   game requires.
16. **Small items** (§2, §3, §5): tables in save data, and the manifest's
   `save_mode` and `save_interval` for when saves are written, with
   `save_commit()` as the game's own checkpoint; `palette.pal` and
   `palette(c, r, g, b)` for a game's own colours; `music_pause`;
   `stat("fps")` and `stat("cpu")`, from a port-supplied clock.
17. **Corrections**: §5 no longer mentions a 256-entry palette, and §9 no
   longer lists 22.05 kHz mono audio as a risk; both predated §8.3 and
   ADR-002. §3 now says what the runtime does: `dt` is 1/60 on every
   machine, `time()` counts from the start of the game, and `palette` is in
   the graphics list; §2 gives every manifest default; §4 no longer
   describes a variable-step flag as existing, nor §9 a `lowlatency` flag;
   §6 lists today's commands.
18. **Lua source only** (§2): until the store exists, packages carry Lua
   source and the runtime refuses bytecode.
19. **Text in English and Tamil** (§3): `print` reads UTF-8 and draws Tamil
   syllables whole from a built-in font made from Noto Sans Tamil (SIL Open
   Font License); a line holding Tamil is 22 pixels tall with its English on
   the Tamil baseline; unknown characters are `?`; `print` returns where the
   text ended, and `text_size` is new.
20. **The remainder is the runtime's** (§4): `math.fmod` and `%` on floats
   no longer come from the C library. On a Pico 2 the SDK's `fmodf` gave
   other bits than the desktop's, and the runtime's self-check failed.
21. **Shade** (§3): `shade(c, lights, edge)`, darkness over the clip
   rectangle with round lights cut out of it and dotted edges.
22. **Notes beside a game** (§6): `pack` leaves out Markdown files, so a
   game's folder can hold a README that does not go into the package.
23. **Storage, package size and cartridges** (§1, §2, §3): flash and PSRAM
   for each chip; a package of up to 64 MB with at most 6 MB in memory at
   once, its parts read as the game uses them; `preload`, `sheet.load` and
   more than one sprite sheet per game, and `stat("active")`; the cartridge
   slot in the first generation, read over quad-SPI like the SD card, with
   saves in the last 512 KB of its flash, written in turn
   (`save_target = "cart"`). §7 no longer says
   cartridges wait for a later generation, nor that cartridge flash is read
   in place. Built since, as item 29 describes.
24. **Measured on a board** (§1, §4, §9): on a Pico 2 at 150 MHz,
   converting a frame to RGB565 takes about 5.1 ms, and the firmware passes
   the maths self-check.
25. **Files the operating system makes** (§6): `pack` leaves out names with
   a `:` (Windows' Zone.Identifier files), `Thumbs.db` and `desktop.ini`,
   and an over-full package is refused with the list of what was packed.
26. **Forgetting a module** (§3): `unrequire(name)`, so a game can free the
   memory of a part it has finished with, such as an earlier chapter.
27. **Small Tamil and button icons** (§3): `font("small")` draws Tamil from
   a second font made at 14 pixels to the em (16 rows instead of 22), for
   labels and HUDs; the twelve button icons are characters U+E000 to
   U+E00B, named by the `buttons` table, so text in any language can show a
   button.
28. **Numbers on a Tamil line** (§3): the Tamil fonts carry the digits 0 to
   9 at their own size, and a line holding Tamil draws its numbers with
   them; English lines keep the 8x8 digits.
29. **The package read in parts** (§2, §3, §6), awaiting approval. Format
   version 2: up to 1024 entries; a header field for where the payload
   starts; the SHA-256 of every 64 KB block of the payload in the front,
   each block checked when it is used, rather than one hash per entry, so
   one sound can be read and checked without its whole bank; the checksum
   and the developer signature over the front only. The active set of 6 MB
   with the oldest unused parts let go; maps other than `map.ooru` checked
   when loaded rather than at start; `sheet.load`, `preload` and
   `stat("active")`. Cartridge saves in slots of whole 4 KB sectors, so the
   largest save has seven, not eight. `pulli cart` writes a cartridge image.
30. **The backdrop** (§3), awaiting approval. `backdrop(name)` sets a
   picture the screen's size, read once and kept, which `cls()` with no
   colour starts each frame from (through `pal()` when colours are
   swapped); `backdrop()` lets it go. On a two-chip console it is sent to
   the graphics chip once, so a still background costs a copy each frame,
   not a full-screen sprite.
