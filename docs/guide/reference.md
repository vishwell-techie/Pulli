# Reference

**தமிழ்:** [ta/reference.md](ta/reference.md)

Every function the console gives a game. Arguments in `[brackets]` may be
left out; the default is given.

**Numbers in drawing calls** may be fractions: they are rounded down to a
whole pixel, and held to the range −32768 to 32767. **Colours** are 0 to 63
and wrap round, so 64 is colour 0 again.

## Callbacks

A game defines these; the console calls them. All are optional.

### `init()`
Called once, when the game starts.

### `update(dt)`
Called 60 times a second. `dt` is the time since the last call, always
1/60 of a second.

### `draw()`
Called after each `update`. If the console runs short of time it skips a
`draw`, never an `update`.

## Drawing

### `cls([c = 0])`
Fill the whole screen with colour `c`. With a backdrop set (see
`backdrop` below), `cls()` with no colour starts the frame from it.

### `pset(x, y, [c = 7])`
Set one pixel.

### `pget(x, y)`
The colour of the pixel that `pset(x, y)` would set, after `camera`; 0 off
the screen.

### `line(x0, y0, x1, y1, [c = 7])`
A straight line between two points, both ends included.

### `rect(x, y, w, h, [c = 7])`
The outline of a box `w` wide and `h` tall, with its top-left corner at
`(x, y)`.

### `rectfill(x, y, w, h, [c = 7])`
A filled box.

### `circ(x, y, [r = 1], [c = 7])`
The outline of a circle centred at `(x, y)` with radius `r`.

### `circfill(x, y, [r = 1], [c = 7])`
A filled circle.

### `shade([c = 0], lights, [edge = 0])`
Night with lights in it. Paints colour `c` over the screen (inside the
`clip` rectangle) everywhere except round the lights. `lights` is a list
of numbers, three for each light: `{x1, y1, r1, x2, y2, r2, ...}`, where
each light is the circle `circfill(x, y, r)` would draw. With an `edge`
of a few pixels, the rim of the light is dotted, which looks softer than a
hard line. Up to 64 lights; `edge` can be up to 32.

```lua
shade(0, {player_x, player_y, 40, lamp_x, lamp_y, 24}, 4)
```

### `print(text, [x = 0], [y = 0], [c = 7])`
Write text on the screen, in English, Tamil or both, with its top at `y`.
English letters are 8 × 8 pixels. Tamil is drawn a syllable at a time, each
as wide as it needs, and a line holding Tamil is 22 pixels tall (16 after
`font("small")`), with any English on it lowered to sit on the same line.
Numbers on a line with Tamil are drawn at the Tamil size; on an English
line they are 8 × 8 like the letters. A character Pulli has no
letter for shows as `?`. Numbers and other values are turned into text.
Returns the `x` where the next letter would go. This draws on the screen;
to print to the terminal, use `dbg`.

### `text_size(text)`
The width and height of `text` in pixels, without drawing it: the width of
its widest line and the height of all its lines. Use it to centre text or
size a box; the `text` helper does.


### `font([size = "normal"])`
The size Tamil is drawn and measured at: `"normal"` or `"small"`. The small
size is 16 pixels a line instead of 22, for labels and HUDs. It stays until
you change it, like `camera`. English letters and button icons keep their
size.

### `buttons`
A table of button icons, one for each button: `buttons.left`, `.right`,
`.up`, `.down`, `.a`, `.b`, `.x`, `.y`, `.l`, `.r`, `.start` and `.select`.
Each is a character, so it goes inside text in any language:
`print("Press " .. buttons.a .. " to jump", 8, 8, 7)`. Icons are 8 pixels
tall; `start` and `select` are 12 wide, the rest 8.
### `camera([x = 0], [y = 0])`
Move everything drawn afterwards up and left by `(x, y)`. Set it to the
corner of the world you want on screen, draw the world, then call
`camera()` before drawing a score or other things that stay put. It also
moves `map.draw`.

### `clip([x], [y], [w], [h])`
Draw only inside this box of the screen. `clip()` with nothing, or a width
or height of 0, draws everywhere again.

### `palette([c], [r], [g], [b])`
Give colour `c` a new look: `r`, `g` and `b` are red, green and blue from 0 to
255. `palette(c)` alone returns colour `c`'s red, green and blue now, as the
screen keeps them: `palette(9, 255, 0, 128)` reads back as `255, 0, 132`.
`palette()` with nothing puts the game's own colours back. See
[Art and sound](art-and-sound.md) for giving a game a whole palette of its
own.

### `pal([a], [b])`
Draw colour `a` as colour `b` from now on. `pal()` with nothing puts every
colour back.

### `palt([c], [see_through = true])`
Make colour `c` see-through in sprites, or not. Colour 0 is see-through to
start with. `palt()` with nothing puts that back.

### `fade([amount = 0])`
Darken the whole screen: 0 is normal, 1 is black, 0.5 half way. It sets a
level rather than adding to it, and costs nothing to draw.

## Sprites

### `spr(n, x, y, [w = 1], [h = 1], [flip_x = false], [flip_y = false])`
Draw sprite `n` from `sprites.png` with its top-left at `(x, y)`. `w` and `h`
draw a block of cells, `w` across and `h` down, starting at `n`. Pixels of a
see-through colour are not drawn.

### `sspr(sx, sy, sw, sh, dx, dy, [dw = sw], [dh = sh])`
Draw any rectangle of the sprite sheet, given in pixels, stretched to
`dw` × `dh` on the screen.

### `sheet.load(name)`
Draw sprites from another sheet: every `.png` in the game's folder becomes
a sheet of the same name, `sprites.kolam` from `sprites.png` being the one
in use at the start. `sheet.load("cave.kolam")` makes `spr`, `sspr` and
`map.draw` use `cave.png` from then on. Sprites already drawn stay. An
error if the game has no such sheet.

## Maps

See [Art and sound](art-and-sound.md) for making maps in Tiled.

### `map.load([name = "map.ooru"])`
Load a map from the package. A game with a `map.ooru` starts with it
loaded. Loading a map again undoes any `map.set`. It is an error if the
package has no map of that name.

### `map.size()`
The loaded map's width and height in tiles, or `0, 0` with no map.

### `map.draw(layer, [sx = 0], [sy = 0])`
Draw layer 0 or 1 with its top-left corner at `(-sx, -sy)`, moved by
`camera` like everything else. Different `sx, sy` for each layer make
them scroll at different speeds.

### `map.get(layer, cx, cy)`
The tile at column `cx`, row `cy`, then whether it is flipped across and
whether it is flipped up-down. 0 outside the map.

### `map.set(layer, cx, cy, tile, [flip_x = false], [flip_y = false])`
Change a tile of the loaded map. The package is not changed.

### `map.flags(tile)`
A tile's flags, set in Tiled: a number from 0 to 255. `map.flags(t) & 1` is
1 for a tile marked `solid`.

### `map.objects([layer])`
The loaded map's objects, placed in Tiled on an object layer: a list of
tables, each with `layer`, `name`, `type`, `x`, `y`, `w`, `h` (in pixels),
`tile` for a tile object, and its own custom properties by name. Name an
object layer to have only its objects. Each call makes a new list, so call
it once when the map is loaded.

```lua
for _, o in ipairs(map.objects("spawns")) do
  if o.type == "enemy" then add_enemy(o.x, o.y, o.hp) end
end
```

## Buttons

Buttons are named `"left"`, `"right"`, `"up"`, `"down"`, `"a"`, `"b"`, `"x"`,
`"y"`, `"l"`, `"r"`, `"start"` and `"select"`.

### `btn(b)`
True while button `b` is held.

### `btnp(b)`
True on the frame button `b` goes down. If it stays down, it is true again
24 frames later and then every 6 frames, so holding a direction scrolls a
menu. `"start"` and `"select"` never repeat. For a press that must count
only once, such as a jump, use the `input` helper.

## Sound

See [Art and sound](art-and-sound.md) for adding sound files.

### `sfx(n, [channel = -1])`
Play sound effect `n`. There are 8 channels, 0 to 7. With no channel, it
uses a free one, or the one whose sound started longest ago. `sfx(-1)`
silences every channel; `sfx(-1, c)` silences channel `c`.

### `music(n, [fade_ms = 0], [loop = true])`
Play track `n`, fading it in over `fade_ms` milliseconds while any track
already playing fades out.

### `music_stop([fade_ms = 0])`
Fade the music out and stop it.

### `music_pause([paused = true])`
Hold the music still, and any fade it is in the middle of. Sound effects
carry on. `music_pause(false)` carries on from the same place. Stopping the
music or starting new music also ends a pause.

## Save data

Needs `save_target` in the manifest; see [Getting started](start.md#saving).

### `save(key, value)`
Keep a value. `key` is 1 to 32 letters, digits, `_`, `-` or `.`. `value` is
a number, text, true/false or a table; `nil` removes the key. Returns true,
or false if the key or value is not allowed or the save data is full.

A table may hold numbers, text, true/false and other tables, nested four
deep, with keys that are numbers, text or true/false. A table that holds a
function, is nested deeper or contains itself is refused. `load` gives back
a new table each time.

### `load(key, [default])`
The value kept under `key`, of the same type it was saved with, or
`default` if there is none.

### `save_commit()`
Write the save data now: a checkpoint. It is also written when the game
ends, and with `save_mode = "auto"` in the manifest, every `save_interval`
seconds (10 or more) after a change. Returns true if it worked. Writing
wears flash, so call it at real checkpoints, not every frame.

## Modules

### `require(name)`
Run `name.lua` from the game's package the first time, and return what it
returned, or true if nothing. Asking again returns the same value. If the
game has no `name.lua`, packing supplies the helper of that name; see
[Helpers](helpers.md).

### `unrequire(name)`
Forget a module, so its memory can be freed once nothing else uses what it
returned. The next `require(name)` runs the file again. Returns true if it
was loaded. Useful for levels or chapters the player has finished.

## Loading

A game may be up to 64 MB, but at most 6 MB of it is in memory at once.
Each part is read the first time the game uses it: a module on `require`,
a map on `map.load`, a sheet on `sheet.load`, a sound the first time it
plays. When memory is full, the parts used longest ago are let go and read
again if needed; the sheet and map in use and the sounds playing always
stay. A small game never notices any of this.

### `preload(name, ...)`
Read parts into memory now, behind a loading screen, so nothing is read in
the middle of play: file names as packed, such as `"forest.ooru"` or
`"forest.kolam"`, and `"sfx 12"` or `"music 3"` for one sound. Returns true,
or false if a name is not in the game; the others are still read. An error
if a part is bigger than 6 MB.

### `backdrop([name])`
Set a still background: a picture exactly the screen's size, 320 × 240,
such as `"sky.kolam"` from a `sky.png`. It is read once and kept, and every
`cls()` with no colour starts the frame from it, far faster than drawing it
as a sprite each frame; colours swapped with `pal()` apply to it, so a
fade darkens it too. `backdrop()` with no name lets it go.

## Link

Two consoles joined by a cable exchange short messages. In the window, run
two copies with the same `--link` port:
`python3 tools/pulli.py run mygame 2 --link 7000`.

### `link.status()`
`"off"` with no link hardware, `"waiting"` for the other console, or
`"connected"`.

### `link.side()`
1 or 2 while connected, different on each console, so the two can agree
who leads. `nil` otherwise.

### `link.send(message)`
Send text of up to 64 bytes. At most 8 a frame. Returns false beyond
either limit or when not connected. `string.pack` puts numbers into a
message.

### `link.recv()`
The next message that arrived, or `nil`. Messages arrive whole and in
order, never in the frame they were sent.

## System

### `time()`
Seconds since the game started, counted in frames: it goes up by exactly
1/60 each update.

### `stat(what)`
`stat("frame")`: updates since the game started. `stat("mem")`: Lua memory
in use, in KB. `stat("fps")`: updates a second over the last second.
`stat("active")`: the game's parts in memory, in KB (at most 6144; see
Loading). `stat("cpu")`: the percentage of the last frame's time that `update` and
`draw` used; over 100 means the frame ran late. `fps` and `cpu` are for
finding out why a game is slow, not for the game to act on: they differ from
run to run, and are `nil` where there is no clock to measure with.

### `dbg(...)`
Print the values, separated by tabs, to the terminal. For finding
mistakes; it shows nothing on the console's screen.

### `sys.has(feature)`
True if this console has the feature: `"link"`, `"wifi"`, `"cart"`,
`"rumble"` or `"video"`. Consoles differ; a game should still work without
any of them.

## Fixed point

Optional whole-number arithmetic in 1/65536ths, for games that want exact
results. A game may use floats, fixed point or both, but must do so the
same way on every console. `fix.one` is 65536 and `fix.pi` is 205887.

### `fix.from(n)`
A number as fixed point. A whole number `n` means `n` units.

### `fix.to(a)`
Fixed point as an ordinary number.

### `fix.floor(a)`
The whole part, rounded down.

### `fix.mul(a, b)`
`a` times `b`.

### `fix.div(a, b)`
`a` divided by `b`. Dividing by 0 is an error.

### `fix.sqrt(a)`
The square root. Negative numbers are an error.

### `fix.sin(a)`
Sine of an angle in radians.

### `fix.cos(a)`
Cosine of an angle in radians.

### `fix.atan(y, [x = fix.one])`
The angle of the point `(x, y)`, in radians.

Add, subtract and compare fixed-point numbers with `+`, `-` and `<`.
Everything wraps round past ±32768; `from`, `floor`, `mul`, `div` and `sqrt`
round down, `sin`, `cos` and `atan` to the nearest.

## Lua itself

Games have Lua 5.4's `string`, `table`, `math`, `utf8` and `coroutine`
libraries, and the basic functions such as `pairs`, `ipairs`, `tostring`
and `type`. There is no `io`, `os`, `package` or `debug`, and `load` is the
save-data function above, not Lua's. Numbers are 32-bit: whole numbers
wrap past about ±2.1 billion, and fractions have about seven digits.
`math.random` gives the same sequence every run until `math.randomseed` is
called. `math.sin`, `math.cos`, `^` and the rest give exactly the same
answers on every machine.
