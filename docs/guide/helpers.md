# Helpers

**தமிழ்:** [ta/helpers.md](ta/helpers.md)

Pulli comes with 17 helpers: small libraries, written in Lua, for things
most games need. To use one, require it:

```lua
local timer = require("timer")
```

There is nothing to install or copy. When the game is packed, Pulli sees
the `require` and puts the helper in the package.

Every helper explains itself in the comments at the top of its file in
`sdk/`; that is the full documentation. List them with:

```bash
python3 tools/pulli.py add
```

**Changing a helper.** Copy it into your game, and from then on the game
uses your copy:

```bash
python3 tools/pulli.py add mygame dialog    # copies sdk/dialog.lua into mygame/
```

Helpers that draw words, `text`, `dialog` and `menu`, handle Tamil as well
as English.

## Moving and drawing

| Helper | For | In short |
|---|---|---|
| `move` | moving through a map without passing walls | `move.by(player, dx, dy)` |
| `camera_follow` | a camera that follows the player | `cam:update(x, y, dt)` then `cam:apply()` |
| `anim` | sprite animations by name | `hero:play("walk")`, `hero:draw(x, y)` |
| `tween` | gliding a value to a target | `tween.to(box, { x = 200 }, 0.5)` |
| `particles` | sparks, dust and smoke | `sparks:emit(x, y, 12, style)` |
| `transition` | fading between screens | `transition.through(0.6, load_next_level)` |
| `text` | centred and outlined text, clocks | `text.center("GAME OVER", 100, 8)` |

## Game structure

| Helper | For | In short |
|---|---|---|
| `scene` | title, play and game-over screens | `scene.go("play")` |
| `input` | presses that count once | `input.pressed("a")` |
| `timer` | delays, repeats and cooldowns | `timer.after(2, open_door)` |
| `menu` | a list to choose from | `menu.new({ "Start", "Quit" }, { choose = ... })` |
| `pool` | reusing objects such as bullets | `bullets:get()`, `bullets:free_at(i)` |

## Worlds and stories

| Helper | For | In short |
|---|---|---|
| `dialog` | characters talking, with questions | `dialog.say("Elder", "Welcome!")` |
| `inventory` | what the player carries | `bag:add("potion", 2)` |
| `quest` | what the player has been asked to do | `quest.advance("gems")` |
| `pathfind` | enemies that find their way round walls | `pathfind.find(x1, y1, x2, y2)` |
| `store` | keeping a table in the save data, and reading it back from older saves | `store.save("settings", t)` |

## Examples

- `examples/hello` uses `input` and `text`.
- `examples/catch`, the tutorial game, uses `timer`, `scene`, `text` and
  `particles`.
- `examples/pong` uses `input`, `timer`, `text` and `particles`.
- `examples/talk` uses `dialog`, `inventory`, `quest`, `tween`, `particles`,
  `camera_follow`, `input`, `anim` and `text`.
- `examples/manickam` uses `scene`, `input`, `menu`, `move`, `pathfind`,
  `anim`, `camera_follow`, `timer`, `text`, `transition` and `particles`.

## Helpers and memory

Each helper costs some of your 256 KB of Lua memory: about 5 to 7 KB each,
and about 15 KB for the biggest, `dialog`. `examples/manickam` requires
eleven and, with its own modules, uses about 155 KB on its title screen; its
benchmark takes it to about 230 KB, close to the limit on purpose.
`stat("mem")` shows what is in use.
