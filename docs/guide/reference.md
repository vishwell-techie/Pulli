# Reference

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
Fill the whole screen with colour `c`.

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

### `print(text, [x = 0], [y = 0], [c = 7])`
Write text on the screen. Letters are 8 × 8 pixels. Numbers and other
values are turned into text. This draws on the screen; to print to the
terminal, use `dbg`.

### `camera([x = 0], [y = 0])`
Move everything drawn afterwards up and left by `(x, y)`. Set it to the
corner of the world you want on screen, draw the world, then call
`camera()` before drawing a score or other things that stay put. It also
moves `map.draw`.

### `clip([x], [y], [w], [h])`
Draw only inside this box of the screen. `clip()` with nothing, or a width
or height of 0, draws everywhere again.

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

## Save data

Needs `save_target` in the manifest; see [Getting started](start.md#saving).

### `save(key, value)`
Keep a value. `key` is 1 to 32 letters, digits, `_`, `-` or `.`. `value` is
a number, text or true/false; `nil` removes the key. Returns true, or false
if the key or value is not allowed or the save data is full. For a table,
use the `store` helper.

### `load(key, [default])`
The value kept under `key`, of the same type it was saved with, or
`default` if there is none.

### `save_commit()`
Write the save data now. It is also written when the game ends. Returns
true if it worked.

## Modules

### `require(name)`
Run `name.lua` from the game's package the first time, and return what it
returned, or true if nothing. Asking again returns the same value. If the
game has no `name.lua`, packing supplies the helper of that name; see
[Helpers](helpers.md).

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
in use, in KB.

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
