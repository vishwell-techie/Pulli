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
| Maths (`sin`, `cos`, `^` and the rest) | the engine's own, the same bits on every machine; tested on desktop, not yet run on a board |
| 16.16 fixed point (`fix`) | optional for games; built and tested |
| Link between two consoles | works between two emulator windows; no hardware link yet |
| Sprites and maps | PNG sprite sheets and Tiled maps are imported when a game is packed; a game may bring its own 64 colours |
| SDK helpers | 17, from tween and dialog to pathfind and menus; plain Lua, supplied when a game requires them |
| Game developer's guide | getting started, a tutorial, art and sound, helpers, reference: `docs/guide` |
| Examples | hello, pong, walk, talk, catch |
| Audio | 8 effect channels plus music, built from WAV files; plays in the window; not yet on a board |
| Firmware | compiles for a Pico 2 (RP2350); never run on a board |
| Editor (Pattarai), store (Santhai), launcher (Vaasal) | not started |

## Not implemented yet

Measured against `docs/SPEC.md`:

- `stat("fps")` and `stat("cpu")` have an answer only where the port has
  a clock: the window and the firmware do, the headless runner does not.
- Packages hold Lua source only: bytecode, encrypted and signed packages
  are refused.
- `check` does no static analysis.
- Maps made in Tiled bring across tile layers only, not objects.
- The desktop's Lua heap limit is stricter than the device's will be,
  because Lua values are larger on a 64-bit machine.

## Layout

```
docs/        SPEC.md, the platform contract; guide/, the game developer's guide
runtime/     the engine, shared unchanged by every port
host/        desktop frontends: pulli-host (SDL2 window), pulli-headless
firmware/    RP2350 port (bring-up stage)
sdk/         helpers written in Lua for games to require: tween, dialog and more
tools/       pulli.py command line, reference rasterizer and mixer, font generator
tests/       conformance, package, runtime, maths, audio, asset, SDK, guide, link and example tests
examples/    hello, pong, walk, talk, catch (the tutorial's game)
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

**[Nool, the game developer's guide](docs/guide/README.md)** starts from
nothing and builds a complete game in eight steps, then covers art, sound,
maps, the helpers and every function. What follows is the short version.

```bash
python3 tools/pulli.py new mygame          # scaffold manifest.lua and main.lua
python3 tools/pulli.py run mygame          # play it in a window
python3 tools/pulli.py check mygame        # run 600 frames with no window
python3 tools/pulli.py pack mygame         # write mygame.pulli

python3 tools/pulli.py run examples/pong 3 # 3 = window scale
```

For pictures, draw an 8x8 grid of sprites in any paint program and save it
as `sprites.png` in the game's folder: `spr(n)` draws the n-th one.
`python3 tools/pulli.py palette pulli.gpl` writes the 64 colours for the
paint program to load. For a map, make one in [Tiled](https://www.mapeditor.org)
with 8x8 tiles and `sprites.png` as its tileset, and save it as `map.tmx`
beside it. `examples/walk` does both, and is the fullest example: three
levels, enemies, sound effects and music.

For sound, put `.wav` files in a `sfx/` folder and a `music/` folder inside
the game. `pack` and `run` number them from 0 in order of file name, so
`sfx/0-jump.wav` plays with `sfx(0)` and `music/0-theme.wav` with
`music(0)`. See `examples/pong/sfx`.

To try link play, start two windows with the same port and pick LINK PLAY
in both:

```bash
python3 tools/pulli.py run examples/pong 2 --link 7000 &
python3 tools/pulli.py run examples/pong 2 --link 7000
```

Keys: arrows move, `Z`/`X` are A/B, `A`/`S` are X/Y, `Q`/`W` are L/R, Enter
is start, right Shift is select, Esc quits.

A game can be split over several Lua files: `require("enemies")` runs
`enemies.lua` from the game's folder. The SDK's helpers in `sdk/` are files
of that kind, and a game gets one just by requiring it:

```lua
local tween = require("tween")     -- nothing to copy: packing the game puts it in
```

```bash
python3 tools/pulli.py add                   # lists the helpers
python3 tools/pulli.py add mygame dialog     # copies dialog.lua in, to change it
```

A file in the game's folder is used in place of the SDK's, which is how a
game changes a helper. Each helper explains itself at the top of its file;
`docs/SPEC.md` §3 lists them all, and `examples/talk` uses six of them.

A game is a folder with a `manifest.lua` and a `main.lua`:

```lua
function init()      end   -- once
function update(dt)  end   -- 60 times a second; dt is always 1/60
function draw()      end   -- after each update

-- cls pset pget line rect rectfill circ circfill spr sspr print
-- camera clip pal palt fade   btn btnp   sfx music   save load   time dbg
-- map.load map.size map.draw map.get map.set map.flags   require
-- link.status link.side link.send link.recv   sys.has
-- fix.from fix.to fix.floor fix.mul fix.div fix.sqrt fix.sin fix.cos fix.atan
```

`docs/SPEC.md` §3 is the full API.

## Firmware

Needs `arm-none-eabi-gcc`. The [Pico SDK](https://github.com/raspberrypi/pico-sdk)
is pinned at 2.3.1 and downloaded on the first build (about 120 MB, into
`firmware/build`). To use a copy of your own, set `PICO_SDK_PATH`; it must
be 2.3.0 or newer.

```bash
cmake -S firmware -B firmware/build -G Ninja      # board: pico2
ninja -C firmware/build                           # firmware/build/pulli.uf2
```

It runs Pong with no display and prints update, draw and screen-conversion
times and Lua memory over USB serial once a second. At start-up it prints
whether the maths check passed: the board must compute exactly what the
desktop computes. `-DPULLI_GAME=<folder>`
links in a different game. The board has no buttons yet: for Pong the
firmware taps A every two seconds to get past the title screen, and
`-DPULLI_AUTO_A_SECONDS=<n>` does the same for another game (0 turns it off).

## Changing how things draw or sound

`tools/refgfx.py` is the reference for every drawing call and
`runtime/gfx.c` must match it. After an intended change, update both, run
`python3 tests/test_conformance.py --update`, and look at the new
`tests/golden.png` before committing it. The font lives in
`runtime/font.txt`; `python3 tools/mkfont.py` regenerates `runtime/font.c`.

Sound works the same way: `tools/refaudio.py` is the reference mixer and
`runtime/audio.c` must produce the same samples. `tests/test_audio.py`
compares them, and `pulli-headless --dump-wav out.wav` saves what a game
played.

## Changes and checks

Nothing is pushed to `main`. Work goes on a feature branch and reaches
`main` through a pull request, squash-merged once the CI checks pass.

- `.github/workflows/ci.yml` runs on every pull request and every push to
  `main`: the `desktop` job builds and runs all the tests, and the
  `firmware` job builds the Pico 2 image. Both must pass.
- `.github/workflows/release.yml` runs when a tag such as `v0.1.0` is
  pushed: it tests, builds and attaches the firmware and the example games
  to a GitHub release.
- `.github/rulesets/` holds the rules for `main` and for release tags.
  Import each under Settings, Rules, Rulesets, New ruleset, Import a
  ruleset. Collaborators can push branches and open pull requests; a pull
  request needs a code-owner approval (`.github/CODEOWNERS`), which only
  the owner can give, and only the owner can create release tags.

## Licence

The software is licensed under the Apache License 2.0 (`LICENSE`, with
credits in `NOTICE`). Contributions are accepted under the same terms.

Hardware designs will be released under CERN-OHL-S v2 when they are added;
there are none in this repository yet. The names Pulli, Vaasal and the rest
are not covered by the licence.
