# Contributing to Pulli

Thank you for helping. Pulli is a game platform, a handheld console and the
tools to make games for it; code, art, music, documentation and bug reports
are all welcome.

## Ways to help

- **Try it and report what goes wrong.** Open an issue with what you did,
  what you expected and what happened. A `.pulli` file or a few lines of
  Lua that show the problem help most.
- **Make a game,** or improve an example in `examples/`.
- **Art and music.** The example games need sprites, tilesets, backdrops,
  sound effects and music. See "Art and sound" below.
- **Pattarai,** the workshop in `tools/pattarai/`: tell us what an artist or
  a developer needs from it.
- **Code:** the engine (`runtime/`), the desktop host (`host/`), the
  firmware (`firmware/`), the tools (`tools/`) and the SDK helpers (`sdk/`).

## Build and test

```bash
cmake -S . -B build -G Ninja && ninja -C build && (cd build && ctest --output-on-failure)
cmake -S firmware -B firmware/build -G Ninja && ninja -C firmware/build   # Pico SDK 2.3.1; downloaded if PICO_SDK_PATH is unset
```

The README's "Build and test" section lists what each needs. A change to
behaviour comes with a test in `tests/`.

## Rules of the codebase

- `docs/SPEC.md` is the platform contract. If the spec and the code
  disagree, fix one of them in the same change; a change to the spec is
  proposed in its §10 until it is approved.
- `runtime/` has no platform code and no platform headers; platform work
  goes in `host/` or `firmware/`.
- `tools/refgfx.py` and `runtime/gfx.c` must draw identically: change both,
  run `python3 tests/test_conformance.py --update` and look at
  `tests/golden.png`. `tools/refaudio.py` and `runtime/audio.c` must mix
  identically, sample for sample (`tests/test_audio.py`).
- `runtime/font.c`, `runtime/font_ta.c` and `runtime/font_ta_small.c` are
  generated: edit the `.txt` files beside them and run
  `python3 tools/mkfont.py`.
- Lua is pinned and patched in `cmake/` (32-bit integers and floats, a fixed
  hash seed). Never link the system Lua.
- Python tools use the standard library only (`tools/fontgen/` is the one
  exception, and is never run by the build or the tests).
- `pulli.py pack` supplies the `sdk/` helpers a game requires; examples keep
  no copies.

## Branches and pull requests

Nothing is pushed to `main`. Work on a branch and open a pull request; it
is squash-merged once the CI checks pass and the owner has approved it.
Keep a pull request to one change, and say in it what you tested.

## Art and sound

Each example's art, music and sound are licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), and
contributors are credited in the game and in `NOTICE`. Contribute only work
you made yourself or have the right to license that way, and say if any of
it was made with a generative tool.

What the console draws: a 320 x 240 screen at 60 frames a second; up to
256 colours, each game choosing 64, 128 or 256 of its own (`palette.hex`);
8 x 8 cells, sprite sheets up to 128 KB of pixels; maps made in Tiled. The
developer's guide (`docs/guide/`) and Pattarai's guide (`docs/pattarai.md`)
say more.

## Conduct

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).
Security problems are reported privately, as [SECURITY.md](SECURITY.md)
says.

By contributing, you agree that your contribution is licensed under the
Apache License 2.0 (code) or CC BY 4.0 (the examples' art, music and sound),
as described in the README.
