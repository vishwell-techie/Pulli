# Pulli

Open-source handheld console. Games are written in Lua and played from cartridges or an SD card.
Pulli (புள்ளி) is Tamil for "dot": a pixel is a dot.

## Status

Early bring-up. The runtime (Vaasal) embeds Lua 5.4, loads one cart built into the firmware and
calls its `init()`, `update(dt)` and `draw()` at 30 frames per second. Output is text over USB
serial. There is no display, input, sound, cartridge or SD support yet.

## Layout

| Path | What it is |
| --- | --- |
| `firmware/src` | Vaasal, the portable runtime |
| `firmware/port` | Platform ports: `pico.c` (RP2040 / RP2350), `host.c` (Linux) |
| `carts` | Lua carts; `carts/hello` is the one built into the firmware |

## Build

Needs CMake, Ninja, `arm-none-eabi-gcc` and the [Pico SDK](https://github.com/raspberrypi/pico-sdk)
2.x with `PICO_SDK_PATH` set. Lua is downloaded by CMake on the first configure.

```sh
cd firmware

# RP2040 (Pico); use -DPICO_BOARD=pico2 for RP2350
cmake -S . -B build-pico -DPICO_BOARD=pico -G Ninja
ninja -C build-pico          # copy build-pico/pulli.uf2 to the board in BOOTSEL mode

# Linux, to run carts without hardware
cmake -S . -B build-host -DPULLI_PLATFORM=host -G Ninja
ninja -C build-host
./build-host/pulli ../carts/hello/main.lua
```

`-DPULLI_CART=<file.lua>` builds a different cart into the firmware.

## Writing a cart

```lua
function init() end        -- once, at start
function update(dt) end    -- every frame; dt is the frame time in seconds
function draw() end        -- every frame, after update
```

Carts get Lua's `base`, `coroutine`, `table`, `string`, `math` and `utf8` libraries, plus:

| Call | Returns |
| --- | --- |
| `pulli.time()` | seconds since power-on |
| `pulli.btn(name)` | whether a button is held (always `false` until there is input hardware) |
| `pulli.version` | runtime version string |

Numbers are 32-bit: integers wrap at 2,147,483,647 and floats are single precision.
