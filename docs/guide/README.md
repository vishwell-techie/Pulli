# Nool: making games for Pulli

**தமிழ்:** [ta/README.md](ta/README.md)

Nool (நூல், "book") is the guide to writing games for Pulli. A Pulli game is
a folder of Lua code, pictures and sounds, and it runs the same on a laptop
as it does on the console.

| Page | What it covers |
|---|---|
| [Getting started](start.md) | Building the tools, your first game, how a game is laid out, packing it |
| [Tutorial: Catch](tutorial.md) | A complete small game, built in eight steps |
| [Art and sound](art-and-sound.md) | Sprite sheets, the palette, maps made in Tiled, text in Tamil, sound effects and music |
| [Helpers](helpers.md) | The 17 ready-made Lua helpers: dialog, menus, timers, pathfinding and more |
| [Reference](reference.md) | Every function a game can call |

New to Pulli? Read Getting started, then follow the tutorial. It takes an
afternoon, and the game you end up with is in `examples/catch`.

The console in numbers: a 320 × 240 screen, 64 colours, sprites made of
8 × 8 cells, 60 frames a second, 12 buttons, 8 channels of sound plus music,
and up to 256 KB of memory for your Lua code and data. `docs/SPEC.md` is the
full platform contract, for anyone porting Pulli or building tools for it.
