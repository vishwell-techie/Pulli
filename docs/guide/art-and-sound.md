# Art and sound

Pictures, maps and sounds are made with ordinary tools and dropped into the
game's folder. When the game is packed, Pulli converts them into the forms
the console reads; you never handle those yourself.

## The palette

Every pixel on Pulli is one of 64 colours, numbered 0 to 63:

![The 64 colours](images/palette.png)

- Colours 32 to 63 are darker shades of 0 to 31, exactly 32 apart. So
  `pal(c, c + 32)` swaps a colour for its shadow, which is an easy way to
  dim a sprite.
- **Colour 0 is see-through in sprites.** Use colour 32, also black, for
  solid black.
- Write the palette out for your paint program, and draw with exactly
  these colours:

  ```bash
  python3 tools/pulli.py palette pulli.gpl   # GIMP, Aseprite, Krita
  python3 tools/pulli.py palette pulli.hex   # one colour per line
  python3 tools/pulli.py palette pulli.png   # an 8 x 8 swatch
  ```

## Sprites

Draw your sprites on a grid of 8 × 8 squares and save it as `sprites.png`
in the game's folder.

- The picture's width and height must be multiples of 8, and it may hold
  at most 131,072 pixels (for example 512 × 256).
- Sprites are numbered left to right, then top to bottom, from 0.
  `spr(n, x, y)` draws number `n`.
- A bigger sprite is several cells: `spr(n, x, y, 2, 2)` draws a 16 × 16
  sprite whose top-left cell is `n`.
- See-through pixels (less than half opaque) become colour 0. Every other
  pixel becomes the nearest of colours 1 to 63. If a colour had to change,
  `pack` says so: load the palette into your paint program to avoid it.
- Any PNG works except an interlaced one.

## Maps

Maps are made in [Tiled](https://www.mapeditor.org), a free map editor.

1. In Tiled, make a new map: orthogonal, tile size 8 × 8, not infinite.
2. Add a tileset from `sprites.png`, tile size 8 × 8, with no margin or
   spacing. Tile `n` in Tiled is sprite `n` in the game.
3. Draw on up to two tile layers. The first becomes layer 0, drawn first;
   the second becomes layer 1, drawn on top.
4. Save the map as `map.tmx` in the game's folder.

A game with a `map.ooru` starts with it loaded, so after packing,
`map.draw(0)` and `map.draw(1)` draw it. Other maps, such as `level2.tmx`,
are loaded with `map.load("level2.ooru")`.

**Walls and other tile properties.** In Tiled's tileset view, select a tile
and add a custom property:

- `solid`, a bool: ticked, the tile is a wall. `map.flags(tile) & 1` is then
  1, and the `move` and `pathfind` helpers treat it as a wall.
- `flags`, an int from 0 to 255, for your own uses: eight on-off bits per
  tile, such as "water" or "hurts".

**Things to know:**

- Tile 0 is empty, so maps never draw the sheet's first cell. Keep it blank.
- Tiles may be flipped in Tiled; rotated tiles are refused.
- A map holds at most 32,768 tiles over both layers, for example two
  layers of 128 × 128.
- Object layers are not imported. To place things such as a player's start
  or enemies, draw their tiles on a layer and look for them in `init()`, as
  `examples/walk` does.

## Sound effects and music

Put `.wav` files in a `sfx` folder and a `music` folder inside the game.

```
mygame/
  sfx/0-jump.wav       sfx(0)
  sfx/1-coin.wav       sfx(1)
  music/0-theme.wav    music(0)
```

- Files are numbered from 0 in order of their names, so start names with a
  number to keep the order clear.
- Mono or stereo, 8 to 32 bit, 4,000 to 48,000 samples a second. Plain PCM
  WAV only; export from your audio editor as "WAV, signed 16-bit PCM" if
  unsure.
- Sound effects are kept exactly as they are. Music is stored at a quarter
  of the size, at a small cost in quality.
- Music loops. If the WAV file marks a loop point, it loops from there;
  otherwise from the start. `music(0, 500)` fades it in over half a second,
  and `music_stop(500)` fades it out.
- Up to eight sound effects play at once, with music on top. They add up,
  so leave some headroom: eight loud sounds together distort.

Keep music short and looping. A 12-second loop at 11,025 samples a second
is about 66 KB once packed.
