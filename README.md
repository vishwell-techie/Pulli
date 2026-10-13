# Pulli

An open-source game platform where every game is written in Lua, with a
handheld console to run them on and reference hardware anyone can build.
Pulli (புள்ளி) is Tamil for "dot": a pixel is a dot.

320×240, 64 colours, 8×8 sprite cells, 60 frames a second. Games are single
`.pulli` files. The desktop runtime and the console run the same engine, so
a game behaves the same on a laptop and in the hand.

![The hello example](docs/images/hello.png)

## Status

Software first; hardware comes last.

| Part | State |
|---|---|
| Spec v0.1 | drafted; October 2026 revision awaiting approval (`docs/SPEC.md` §10) |
| Engine: rasterizer, package reader, save store, Lua API | built and tested; not yet the whole API (see "Not implemented yet") |
| Desktop host, windowed and headless | built and tested on Linux (Raspberry Pi 5) |
| Reference rasterizer and conformance suite | passing; the C engine matches it byte for byte |
| Package format and command line | `new`, `pack`, `list`, `unpack`, `run`, `check` |
| Examples | hello, pong |
| Audio | silent |
| Firmware | compiles for a Pico 2 (RP2350); never run on a board |
| Editor (Pattarai), store (Santhai), launcher (Vaasal) | not started |

## Not implemented yet

Measured against `docs/SPEC.md`:

- Sound: `sfx` and `music` are accepted and silent.
- Maps: `map.load`, `map.set` and `map.flags` are missing and the map file
  format is undefined, so `map.draw` has nothing to draw.
- `save` refuses tables; numbers, strings and booleans work.
- `stat("fps")` and `stat("cpu")` return nil.
- No way to load a custom palette.
- Packages hold Lua source only: bytecode, encrypted and signed packages
  are refused.
- No PNG or Tiled importers, and `check` does no static analysis.
- The desktop's Lua heap limit is stricter than the device's will be,
  because Lua values are larger on a 64-bit machine.

## Layout

```
docs/        SPEC.md, the platform contract
runtime/     the engine, shared unchanged by every port
host/        desktop frontends: pulli-host (SDL2 window), pulli-headless
firmware/    RP2350 port (bring-up stage)
tools/       pulli.py command line, reference rasterizer, font generator
tests/       conformance, package, runtime and example tests
examples/    hello, pong
cmake/       pinned Lua build shared by host and firmware
```

`runtime/` contains no platform code. Porting means writing a backend and a
main loop like the ones in `host/` and `firmware/`; the engine and every
pixel it draws stay the same, and `tests/` exists to keep that true.

## Build and test

Needs a C compiler, CMake 3.16+, Python 3 and, for the window, SDL2. Lua is
downloaded and built by CMake on the first configure; the system's Lua is
not used.

```bash
# Debian, Ubuntu, Raspberry Pi OS
sudo apt install build-essential cmake ninja-build python3 libsdl2-dev
# macOS
brew install cmake ninja sdl2

cmake -S . -B build -G Ninja
ninja -C build
(cd build && ctest --output-on-failure)
```

Without SDL2 everything except the windowed `pulli-host` still builds and
the tests still run.

## Make and run a game

```bash
python3 tools/pulli.py new mygame          # scaffold manifest.lua and main.lua
python3 tools/pulli.py run mygame          # play it in a window
python3 tools/pulli.py check mygame        # run 600 frames with no window
python3 tools/pulli.py pack mygame         # write mygame.pulli

python3 tools/pulli.py run examples/pong 3 # 3 = window scale
```

Keys: arrows move, `Z`/`X` are A/B, `A`/`S` are X/Y, `Q`/`W` are L/R, Enter
is start, right Shift is select, Esc quits.

A game is a folder with a `manifest.lua` and a `main.lua`:

```lua
function init()      end   -- once
function update(dt)  end   -- 60 times a second; dt is always 1/60
function draw()      end   -- after each update

-- cls pset pget line rect rectfill circ circfill spr sspr print
-- camera clip pal palt fade   btn btnp   sfx music   save load   time dbg
```

`docs/SPEC.md` §3 is the full API.

## Firmware

Needs the [Pico SDK](https://github.com/raspberrypi/pico-sdk) 2.x with
`PICO_SDK_PATH` set, and `arm-none-eabi-gcc`.

```bash
cmake -S firmware -B firmware/build -G Ninja      # board: pico2
ninja -C firmware/build                           # firmware/build/pulli.uf2
```

It runs Pong with no display and prints update, draw and screen-conversion
times and Lua memory over USB serial once a second. `-DPULLI_GAME=<folder>`
links in a different game. The board has no buttons yet: for Pong the
firmware taps A every two seconds to get past the title screen, and
`-DPULLI_AUTO_A_SECONDS=<n>` does the same for another game (0 turns it off).

## Changing how things draw

`tools/refgfx.py` is the reference for every drawing call and
`runtime/gfx.c` must match it. After an intended change, update both, run
`python3 tests/test_conformance.py --update`, and look at the new
`tests/golden.png` before committing it. The font lives in
`runtime/font.txt`; `python3 tools/mkfont.py` regenerates `runtime/font.c`.

## Licence

Planned: MIT or Apache-2.0 for software and CERN-OHL-S v2 for hardware.
The licence files have not been added yet.
