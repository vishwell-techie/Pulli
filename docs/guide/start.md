# Getting started

**தமிழ்:** [ta/start.md](ta/start.md)

## Build the tools

You need a C compiler, CMake, Ninja and Python 3. SDL2 is needed for the
game window; without it everything else still works.

```bash
# Debian, Ubuntu, Raspberry Pi OS
sudo apt install build-essential cmake ninja-build python3 libsdl2-dev
# macOS
brew install cmake ninja sdl2
```

Then, in the Pulli folder:

```bash
cmake -S . -B build -G Ninja
ninja -C build
```

The first build downloads Lua, which Pulli builds itself so that every
machine runs exactly the same version.

## Your first game

```bash
python3 tools/pulli.py new mygame
python3 tools/pulli.py run mygame
```

`new` makes a folder with two files, and `run` opens it in a window, three
times the console's 320 × 240 unless you give another size after the game:
`python3 tools/pulli.py run mygame 2` for twice. Move the square with the
arrow keys. Escape closes the window.

| Console | Keyboard |
|---|---|
| D-pad | arrow keys |
| A, B | Z, X |
| X, Y | A, S |
| L, R | Q, W |
| START | Enter |
| SELECT | right Shift |

## What is in a game

A game is a folder. Two files are required:

- **`manifest.lua`** says what the game is called and what it needs.
- **`main.lua`** is the game.

```lua
-- manifest.lua
return {
  id      = "com.yourname.mygame",   -- unique: your name, then the game's
  title   = "My Game",
  author  = "Your Name",
  version = "0.1.0",
  spec    = 1,                       -- the version of Pulli it was written for
}
```

Anything else in the folder is optional:

| File or folder | Becomes |
|---|---|
| `sprites.png` | the sprite sheet: see [Art and sound](art-and-sound.md) |
| `map.tmx`, or any other `.tmx` | a map made in Tiled |
| `sfx/*.wav` | sound effects: `sfx(0)` plays the first file by name |
| `music/*.wav` | music: `music(0)` plays the first |
| `palette.hex` or `palette.gpl` | 64 colours of your own instead of Pulli's: see [Art and sound](art-and-sound.md) |
| any other `.lua` file | a module, loaded with `require("name")` |

## How a game runs

```lua
function init()       -- once, when the game starts
end

function update(dt)   -- 60 times a second: move things, read buttons
end

function draw()       -- after every update: draw the screen
end
```

`dt` is the time since the last update, always 1/60 of a second. Multiply
speeds by it, as in `x = x + 100 * dt` for 100 pixels a second, and your game
reads clearly even though the steps are fixed.

Keep `update` for changing things and `draw` for drawing them. If the
console ever runs short of time it skips a `draw`, never an `update`, so
the game stays correct even when the picture stutters.

The screen is 320 pixels across and 240 down. `(0, 0)` is the top-left
corner, and y grows downwards.

## Finding mistakes

`dbg(...)` prints to the terminal you started the game from. It is the
quickest way to see what a value is:

```lua
dbg("score", score, "lives", lives)
```

When the game has an error, it stops and the message says which file and
line. `print()` draws text on the game screen; it does not reach the
terminal.

## Checking without a window

```bash
python3 tools/pulli.py check mygame        # run 600 frames, report errors and memory
python3 tools/pulli.py check mygame 3600   # a minute of game time
```

## Packing a game

```bash
python3 tools/pulli.py pack mygame         # writes mygame.pulli
python3 tools/pulli.py list mygame.pulli   # what is inside
```

A `.pulli` file is the whole game in one file: code, pictures, maps and
sounds, converted into the forms the console reads. It is what you share.
Notes in Markdown, such as a `README.md` about the game, stay in the folder
and are left out.

## Saving

To keep something between plays, such as a best score, add two lines to
the manifest:

```lua
  save_target = "sd",    -- keep save data on the console's card
  save_size   = 1024,    -- bytes it may use, up to 65536
```

Then `save("best", score)` keeps a value and `load("best", 0)` reads it
back, giving `0` the first time. Values may be numbers, text or
true/false, or a table of those (tables may be nested four deep).

Save data is written when the game ends, and `save_commit()` writes it at
once, so call that at checkpoints: reaching a new level, a save point, the
end of a round. A crash or a flat battery loses what was saved since the
last of these.

To have it written in the background too, add two lines to the manifest:

```lua
  save_mode     = "auto",
  save_interval = 60,    -- seconds between writes: you choose, 10 or more (60 if left out)
```

A change is then written once `save_interval` seconds have passed since the
last write, a checkpoint included. Flash wears with every write, so the
shortest interval allowed is 10 seconds, and a game should call
`save_commit()` at real checkpoints, not every frame.

## Limits worth knowing

- **Memory:** your Lua code and data get up to 256 KB. `stat("mem")` says
  how much is in use, in KB. Making new tables every frame fills memory
  with garbage; make them once and reuse them (the `pool` helper helps).
- **Lua:** Lua 5.4 with 32-bit numbers. Whole numbers run from about −2.1
  billion to 2.1 billion and wrap around past that. Fractions have about
  seven digits of precision.
- **No files:** a game cannot read or write files. Everything it needs is
  in its package, and it keeps data with `save`.
- **Same everywhere:** the same game gives the same results on every
  machine, down to the last bit, including random numbers. A game that
  wants different random numbers each time should call
  `math.randomseed(stat("frame"))` when the player presses a button.
