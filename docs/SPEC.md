# Pulli Platform Specification — v0.1 (DRAFT, for review)

Status: **§8 questions resolved and locked** (8x8 cells, 320x240 locked,
64-colour palette, named Pulli). Architecture revised per ADR-001 (GPU
coprocessor) and ADR-002 (audio). Remainder awaiting approval.
Revised October 2026 while the runtime was first built and tested: §10 lists
what was added or changed, all of it awaiting approval.
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
with DMA to the panel. **Still must be measured at bring-up.**

---

## 2. Game package format (`.pulli`)

A `.pulli` is a flat, uncompressed, memory-mappable archive. Deliberately *not*
ZIP: no zlib on the MCU, and cartridge flash should be XIP-readable so assets
are read in place rather than copied to RAM.

```
offset  size  field
0       4     magic "PULI"
4       1     format version (u8)
5       1     flags (u8): 0x01 encrypted, 0x02 signed, 0x04 dev build
6       2     entry count (u16 LE)
8       4     total size (u32 LE)
12      4     crc32 of payload (u32 LE)
16      N*40  entry table
...           payload (each entry 4-byte aligned)
total   ...   the seal: licence and signature (see below)

entry (40 bytes):
0       32    name, NUL-padded ASCII
32      4     offset from file start (u32 LE)
36      4     length (u32 LE)
```

A package holds at most 64 entries. Entry names are 1 to 32 printable ASCII
characters with no path separators; a 32-character name has no terminating
NUL. `total size` and the checksum cover the header, table and payload: the
checksum is over every byte from offset 16 to `total size`. The seal comes
after and is covered by neither. A reader must check every offset and
length before using it, and must accept a file that is longer than the
package and its seal (a cartridge holds them at the start of a larger flash
region).

Required entries: `manifest.lua`, `main.lua`.
Conventional: `sprites.kolam`, `map.ooru`, `sfx.oli`, `music.isai`, `icon.kolam`.
The asset extensions follow the tools that make them: Kolam
for sprites, Ooru for maps, Oli for sound effects, Isai for music.

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

The signature is made over the package, bytes 0 to `total size`. Because
the seal lies outside the package's size and checksum, a licence or a
signature can be replaced without changing one byte of the package: the
store keeps one build of a game and attaches a seal per purchase.

| Kind | Licence | Signature |
|---|---|---|
| 0, developer | empty; the game runs on any device | the SHA-256 of the package, 32 bytes |
| 1 and up | reserved for the store | reserved for the store |

Every package a developer builds gets the developer seal automatically. A
developer signature catches a damaged or altered file; it proves nothing
about who made the package, since anyone can compute it. A runtime refuses
a package with no seal, with a signature that does not match, or with a
kind it does not know.

Lua sources are stored as **precompiled bytecode** (`luac -s`) in release
builds and as plain source in dev builds. The loader accepts either.
*Not yet: the runtime loads source only and refuses bytecode. Lua does not
verify bytecode, so accepting it from a package means trusting whoever built
the package. How release builds should ship is still open.*

### sprites.kolam (draft)

```
offset  size  field
0       4     magic "KLM1"
4       2     width in pixels (u16 LE), a multiple of 8
6       2     height in pixels (u16 LE), a multiple of 8
8       w*h   pixels, 8-bit palette indices, row by row
```

At most 128 KB of pixels (§1). The pixels are used in place, never copied.
`spr(n)` counts 8x8 cells left to right, top to bottom. The formats of
`map.ooru`, `sfx.oli` and `music.isai` are not yet defined.

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
  lua_heap    = 192,                      -- KB requested, max 256 (§1)
  icon        = "icon.kolam",
}
```

The launcher reads only the manifest — never executes `main.lua` — to build
the game list. Manifest is evaluated in a sandbox with no I/O: no libraries
at all, 64 KB of memory and a limit on how long it may run.

`id`, `title` and `spec` are required. `id` may use letters, digits, `.`,
`_` and `-`, and may not start with `.`; it names the game's save data.
Defaults: `save_target = "none"`, `save_size = 4096`, `lua_heap = 256`.
A game whose `spec` is newer than the runtime is refused. Unknown fields
are ignored.

---

## 3. Lua API — v0.1

### Lifecycle

```lua
function init()      end  -- once, after assets mount
function update(dt)  end  -- 60 Hz, dt in seconds (fixed 1/60 on device)
function draw()      end  -- 60 Hz, after update
```

If `update` or `draw` overruns its budget the engine drops the *draw*, never
the *update*. Logic stays deterministic; visuals degrade.

### Graphics

```lua
cls(c)                             -- clear to palette index c (default 0)
pset(x, y, c)   pget(x, y)
line(x0,y0,x1,y1,c)
rect(x,y,w,h,c) rectfill(x,y,w,h,c)
circ(x,y,r,c)   circfill(x,y,r,c)
spr(n, x, y, w, h, flip_x, flip_y) -- n = sprite index; w,h in 8px cells
sspr(sx,sy,sw,sh, dx,dy, dw,dh)    -- stretched blit
print(text, x, y, c)
camera(x, y)                       -- world -> screen offset
clip(x, y, w, h)                   -- nil = reset
pal(a, b)                          -- remap palette index a -> b
palt(c, is_transparent)
fade(amount)                       -- 0..1, palette-level, free
```

**Arguments.** Every coordinate and size may be a float; it is rounded down
to a whole pixel and held to the range -32768..32767 (the range the GPU
command format carries, ADR-001). Colour indices wrap at 64, so `c` and
`c + 64` are the same colour; that holds for sprite pixels too. `pal()` and
`palt()` with no arguments restore the defaults. `fade` sets a level and
does not accumulate: `fade(0.5)` every frame holds half brightness, and
`fade(0)` restores the picture. Shapes may cross the screen edge freely.

### Map

```lua
map.load("map.ooru")
map.draw(layer, sx, sy)            -- layer 0 = bg, 1 = fg
map.get(layer, cx, cy)  map.set(layer, cx, cy, tile)
map.flags(tile)                    -- 8 collision/meta bits per tile
```

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
sfx(n, channel)   -- channel optional, -1 = auto
music(n, fade_ms)
music_stop(fade_ms)
```

### Save data

```lua
save(key, value)   -- value: number, string, boolean, or flat table
load(key, default)
save_commit()      -- flush to storage; engine also auto-commits on exit
```

Saves are a key-value blob capped at `save_size`. No filesystem access from
games — ever. This is what makes cartridge/SD parity trivial.

Keys are 1 to 32 characters from letters, digits, `_`, `-` and `.`. `save`
returns `true`, or `false` if the key is bad, the value is of an unsupported
type, the store is full, or the game has no `save_target`. Saving `nil`
deletes the key. `load` returns the value with the type it was saved with.
*Not yet: flat tables.*

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
time()             -- seconds since boot, float
stat("fps") stat("mem") stat("cpu")
dbg(...)           -- printf to host console / device serial; stripped in release
```

### Batteries (Lua-level, shipped as SDK source, not engine)

`dialog`, `inventory`, `quest`, `camera_follow`, `particles`, `tween`.
Deliberately implemented **in Lua**, in the SDK, so developers can read, fork
and replace them. Nothing here is privileged.

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
work. The host may run in variable-step mode for debugging, behind a flag.

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
  in the last place of the true value. `math.sqrt`, `math.fmod`, `%`, `//`,
  `math.floor` and `math.ceil` are left to the platform, because IEEE 754
  defines their results exactly.
- **A float unit is optional.** Games always compute in 32-bit IEEE floats.
  A chip with a float unit uses it; a chip without one does the same
  arithmetic in software and gets the same bits, only more slowly. A port
  never switches a game to a different kind of number, because that would
  change how the game behaves.
- **Fixed point is a choice, not a fallback.** The `fix` functions (§3) are
  integer arithmetic and are equally exact everywhere. A game may use them,
  floats, or both, but the same way on every device.
- **A port proves it.** The runtime carries a self-check that runs these
  functions, plain float arithmetic and fixed point over a fixed set of
  inputs and compares a checksum of the results with a recorded value. A
  port is not conformant until it passes.

Not yet covered: turning a number into text and text into a number
(`tostring`, `string.format`, `tonumber`, and decimal numbers written in
source) still goes through the C library. A game whose logic depends on the
exact digits may differ between desktop and device.

---

## 5. Coordinate & color conventions

- Origin top-left, +y down, integer pixel centers.
- Palette index 0 is transparent for sprites by default (`palt` overridable).
- The default 64-colour palette (§8.3) is built into the runtime. Games
  may load their own 64-entry palette; the API for that is not yet defined.

---

## 6. Toolchain

```
pulli new <name>       scaffold a project
pulli run              build + launch in the host emulator, hot reload
pulli pack             produce <name>.pulli
pulli check            static checks: API misuse, budget overruns, GC churn
pulli flash            push to device over USB
```

Today the CLI is `python3 tools/pulli.py`. `new`, `pack`, `list`, `unpack`
and `run` work; `check` runs the game with no window and reports errors and
peak memory, without the static checks yet; hot reload and `flash` do not
exist yet.

---

## 7. Deliberate deviations from the earlier plan

| Earlier plan | Now | Why |
|---|---|---|
| RP2040 as GPU over SPI command stream | **Second RP2350 as GPU over PIO parallel** | Same idea, better part: 2x SRAM, one part number, shared source (ADR-001) |
| SPI display | **8080 8-bit parallel** | The actual unlock for 60 FPS; only affordable because a dedicated chip can spend the pins |
| RGB565 framebuffer | 8-bit indexed + palette | Halves RAM, enables free fades/flashes |
| 44.1 kHz stereo on device | **44.1 kHz stereo retained** | Core 1 is free once the display moves off-CPU (ADR-002) |
| `.pulli` = folder/zip | Flat XIP-friendly archive | No zlib on MCU; cartridge flash reads in place |
| Cartridges in v1 | SD only in v1 | Cartridges follow in a later generation |

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
  RPGs; a `lowlatency` manifest flag exists for twitch games.
- **Index-to-RGB565 conversion cost is still unmeasured**, now on the GPU
  chip where it has more room to be slow.
- **Lua GC pauses.** Mitigation is stepped GC per frame plus object pooling in
  the SDK, but this is unproven at this scale on Cortex-M33.
- **Audio can still sound cheap at 44.1 kHz stereo.** ADR-002 settled the
  sample rate; what people hear is the analog stage and the speaker's back
  volume. Needs a listening test early, not late.

---

## 10. Changes in this revision (October 2026, awaiting approval)

Made while building and testing the first runtime. Each is implemented and
covered by `tests/`; none is frozen.

1. **Names.** The platform is Pulli; the package is `.pulli` with magic
   `PULI`; asset entries are `.kolam`, `.ooru`, `.oli`, `.isai`.
2. **Lua number model** (§1, §4): 32-bit integers and floats, one pinned Lua
   build for host and device.
3. **Determinism rules** (§4): fixed random seed, fixed hash seed, no fused
   multiply-add.
4. **Argument conventions** (§3): fractions round down, coordinates are held
   to 16 bits, colour indices wrap at 64, `pal()`/`palt()` reset, `fade`
   sets a level instead of accumulating.
5. **Package limits** (§2): 64 entries, name rules, what the checksum
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
13. **Corrections**: §5 no longer mentions a 256-entry palette, and §9 no
   longer lists 22.05 kHz mono audio as a risk; both predated §8.3 and
   ADR-002.
