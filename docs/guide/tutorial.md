# Tutorial: Catch

**தமிழ்:** [ta/tutorial.md](ta/tutorial.md)

In this tutorial you build **Catch**: gems fall from the sky and you move a
basket to catch them. Miss three and the game is over. By the end it has
pictures, a title screen, a saved best score, sound and sparks.

Each step below is the whole of `main.lua` at that point, so you can copy
it in and run it. Read the notes after each one: they explain what is new.
The finished game is in `examples/catch`.

## Before you start

Make the game's folder and copy in the pictures and sounds the tutorial uses:

```bash
python3 tools/pulli.py new catch
cp examples/catch/sprites.png catch/
cp -r examples/catch/sfx catch/
```

Run it after each step with `python3 tools/pulli.py run catch`.

## Step 1: something on the screen

```lua
-- step 1: something on the screen

function init()
end

function update(dt)
end

function draw()
  cls(1)                              -- clear the screen to dark blue
  print("CATCH", 140, 40, 7)          -- text at x = 140, y = 40, in white
  rectfill(144, 220, 32, 8, 4)        -- the basket: a brown box 32 wide, 8 tall
end
```

- `init`, `update` and `draw` are the three functions every game has. For
  now only `draw` does anything.
- `cls(1)` fills the screen with colour 1. Colours are numbers from 0 to 63;
  [Art and sound](art-and-sound.md) shows them all.
- `print(text, x, y, colour)` writes text. Each letter is 8 pixels wide.
- `rectfill(x, y, width, height, colour)` draws a filled box.

## Step 2: move the basket

```lua
-- step 2: move the basket

local basket_x = 144
local SPEED = 120                     -- pixels a second

function init()
end

function update(dt)
  if btn("left") then basket_x = basket_x - SPEED * dt end
  if btn("right") then basket_x = basket_x + SPEED * dt end
  basket_x = math.max(0, math.min(320 - 32, basket_x))   -- stay on the screen
end

function draw()
  cls(1)
  print("CATCH", 140, 40, 7)
  rectfill(basket_x, 220, 32, 8, 4)
end
```

- `btn("left")` is true while the left button is held.
- The basket moves `SPEED * dt` each frame: 120 pixels a second.
- `math.max` and `math.min` keep it on the screen. The screen is 320 wide
  and the basket 32, so its left edge must stay between 0 and 288.

## Step 3: a falling gem

```lua
-- step 3: a falling gem

local basket_x = 144
local SPEED = 120
local gem_x, gem_y = 160, 0
local gem_speed = 60

-- Put the gem back at the top, somewhere new.
local function drop_gem()
  gem_x = math.random(8, 312)
  gem_y = -8
end

function init()
  drop_gem()
end

function update(dt)
  if btn("left") then basket_x = basket_x - SPEED * dt end
  if btn("right") then basket_x = basket_x + SPEED * dt end
  basket_x = math.max(0, math.min(320 - 32, basket_x))

  gem_y = gem_y + gem_speed * dt
  if gem_y > 240 then drop_gem() end  -- fell off the bottom
end

function draw()
  cls(1)
  print("CATCH", 140, 40, 7)
  circfill(gem_x, gem_y, 4, 10)       -- a yellow circle of radius 4
  rectfill(basket_x, 220, 32, 8, 4)
end
```

- `local function` makes a function only this file can see. Give each job
  its own small function and the game stays easy to read.
- `math.random(8, 312)` picks a whole number between 8 and 312.
- When the gem falls past the bottom of the screen, it starts again at the top.

## Step 4: catch it and score

```lua
-- step 4: catch it and score

local basket_x = 144
local SPEED = 120
local gem_x, gem_y = 160, 0
local gem_speed = 60
local score = 0

local function drop_gem()
  gem_x = math.random(8, 312)
  gem_y = -8
end

-- Is the gem touching the basket?
local function caught()
  return gem_y >= 216 and gem_y <= 228
     and gem_x >= basket_x and gem_x <= basket_x + 32
end

function init()
  drop_gem()
end

function update(dt)
  if btn("left") then basket_x = basket_x - SPEED * dt end
  if btn("right") then basket_x = basket_x + SPEED * dt end
  basket_x = math.max(0, math.min(320 - 32, basket_x))

  gem_y = gem_y + gem_speed * dt
  if caught() then
    score = score + 1
    gem_speed = gem_speed + 5           -- a little faster each time
    drop_gem()
  elseif gem_y > 240 then
    drop_gem()
  end
end

function draw()
  cls(1)
  print("SCORE " .. score, 4, 4, 7)
  circfill(gem_x, gem_y, 4, 10)
  rectfill(basket_x, 220, 32, 8, 4)
end
```

- `caught()` checks whether the gem is inside the basket's box. Checks like
  this are how most games decide that two things touch.
- `..` joins text: `"SCORE " .. score` becomes `"SCORE 3"`.
- Each catch makes the gem fall a little faster.

## Step 5: pictures instead of shapes

```lua
-- step 5: pictures instead of shapes

local basket_x = 144
local SPEED = 120
local gem_x, gem_y = 160, 0
local gem_speed = 60
local score = 0

local BASKET, GEM = 1, 3              -- their numbers on sprites.png

local function drop_gem()
  gem_x = math.random(4, 308)
  gem_y = -8
end

local function caught()
  return gem_y + 8 >= 218 and gem_y <= 226
     and gem_x + 8 >= basket_x and gem_x <= basket_x + 16
end

function init()
  drop_gem()
end

function update(dt)
  if btn("left") then basket_x = basket_x - SPEED * dt end
  if btn("right") then basket_x = basket_x + SPEED * dt end
  basket_x = math.max(0, math.min(320 - 16, basket_x))

  gem_y = gem_y + gem_speed * dt
  if caught() then
    score = score + 1
    gem_speed = gem_speed + 5
    drop_gem()
  elseif gem_y > 240 then
    drop_gem()
  end
end

function draw()
  cls(1)
  print("SCORE " .. score, 4, 4, 7)
  spr(GEM, gem_x, gem_y)
  spr(BASKET, basket_x, 220, 2, 1)    -- two sprites wide, one tall
end
```

- `sprites.png` is a grid of 8 × 8 pictures. `spr(3, x, y)` draws picture
  number 3, counting from 0 at the top-left. Open `sprites.png` in a paint
  program to see them.
- The basket is two pictures side by side, so it is drawn with
  `spr(1, x, y, 2, 1)`: two cells wide and one tall.
- Now the basket is 16 pixels wide, the edges and the catch box change to
  match.

## Step 6: many gems, three lives

```lua
-- step 6: many gems, three lives

local timer = require("timer")        -- an SDK helper: nothing to install

local SPEED = 120
local BASKET, GEM, HEART, NO_HEART = 1, 3, 4, 5

local basket_x
local gems = {}                       -- every gem falling, each { x, y }
local score, lives, gem_speed
local over

local function drop_gem()
  gems[#gems + 1] = { x = math.random(4, 308), y = -8 }
end

local function caught(g)
  return g.y + 8 >= 218 and g.y <= 226
     and g.x + 8 >= basket_x and g.x <= basket_x + 16
end

local function start()
  basket_x, score, lives, gem_speed, over = 144, 0, 3, 50, false
  gems = {}
  timer.clear()
  timer.every(1.2, drop_gem)          -- a new gem every 1.2 seconds
end

function init()
  start()
end

function update(dt)
  if over then
    if btnp("a") then start() end
    return
  end
  timer.update(dt)

  if btn("left") then basket_x = basket_x - SPEED * dt end
  if btn("right") then basket_x = basket_x + SPEED * dt end
  basket_x = math.max(0, math.min(320 - 16, basket_x))

  -- Go through the gems backwards, so taking one out is safe.
  for i = #gems, 1, -1 do
    local g = gems[i]
    g.y = g.y + gem_speed * dt
    if caught(g) then
      table.remove(gems, i)
      score = score + 1
      gem_speed = gem_speed + 2
    elseif g.y > 240 then
      table.remove(gems, i)
      lives = lives - 1
      if lives == 0 then over = true end
    end
  end
end

function draw()
  cls(1)
  for i = 1, #gems do spr(GEM, gems[i].x, gems[i].y) end
  spr(BASKET, basket_x, 220, 2, 1)
  print("SCORE " .. score, 4, 4, 7)
  for i = 1, 3 do spr(i <= lives and HEART or NO_HEART, 286 + i * 9, 3) end
  if over then
    print("GAME OVER", 124, 100, 8)
    print("PRESS A", 132, 116, 7)
  end
end
```

- `require("timer")` loads one of Pulli's ready-made helpers. There is
  nothing to install: packing the game puts the helper in. `timer.every`
  calls `drop_gem` every 1.2 seconds, and `timer.update(dt)` keeps it
  running.
- `gems` is a table of tables. Each gem is `{ x = ..., y = ... }`, and
  `#gems` is how many there are.
- The loop goes backwards, from the last gem to the first, so that removing
  one with `table.remove` never skips the next.
- `btnp("a")` is true on the frame A is pressed. Here it restarts the game.

## Step 7: a title screen, and the best score kept

```lua
-- step 7: a title screen, and the best score kept

local timer = require("timer")
local scene = require("scene")        -- the game's screens, each in its own table
local text = require("text")

local SPEED = 120
local BASKET, GEM, HEART, NO_HEART = 1, 3, 4, 5

local basket_x
local gems = {}
local score, lives, gem_speed
local best = 0

local function drop_gem()
  gems[#gems + 1] = { x = math.random(4, 308), y = -8 }
end

local function caught(g)
  return g.y + 8 >= 218 and g.y <= 226
     and g.x + 8 >= basket_x and g.x <= basket_x + 16
end

local function draw_field()
  cls(1)
  for i = 1, #gems do spr(GEM, gems[i].x, gems[i].y) end
  spr(BASKET, basket_x, 220, 2, 1)
  print("SCORE " .. score, 4, 4, 7)
  for i = 1, 3 do spr(i <= lives and HEART or NO_HEART, 286 + i * 9, 3) end
end

scene.add("title", {
  update = function(dt)
    if btnp("a") then
      math.randomseed(stat("frame"))  -- a different game each time
      scene.go("play")
    end
  end,
  draw = function()
    cls(1)
    text.center("CATCH", 80, 10)
    text.center("BEST " .. best, 110, 7)
    text.center("PRESS A", 150, 6)
  end,
})

scene.add("play", {
  enter = function()
    basket_x, score, lives, gem_speed = 144, 0, 3, 50
    gems = {}
    timer.clear()
    timer.every(1.2, drop_gem)
  end,
  update = function(dt)
    timer.update(dt)
    if btn("left") then basket_x = basket_x - SPEED * dt end
    if btn("right") then basket_x = basket_x + SPEED * dt end
    basket_x = math.max(0, math.min(320 - 16, basket_x))
    for i = #gems, 1, -1 do
      local g = gems[i]
      g.y = g.y + gem_speed * dt
      if caught(g) then
        table.remove(gems, i)
        score = score + 1
        gem_speed = gem_speed + 2
      elseif g.y > 240 then
        table.remove(gems, i)
        lives = lives - 1
        if lives == 0 then scene.go("over") end
      end
    end
  end,
  draw = draw_field,
})

scene.add("over", {
  enter = function()
    if score > best then
      best = score
      save("best", best)              -- kept for next time
    end
  end,
  update = function(dt)
    if btnp("a") then scene.go("title") end
  end,
  draw = function()
    draw_field()
    text.center("GAME OVER", 100, 8)
    text.center("PRESS A", 116, 7)
  end,
})

function init()
  best = load("best", 0)              -- 0 the first time
  basket_x, score, lives = 144, 0, 3
  scene.go("title")
end

function update(dt) scene.update(dt) end
function draw() scene.draw() end
```

- `scene` is another helper. Each screen of the game is a table with its
  own `update` and `draw`, and `enter` runs when the screen starts.
  `scene.go("play")` changes screen.
- `text.center` from the `text` helper centres a line on the screen.
- `save("best", best)` keeps the best score and `load("best", 0)` reads it
  back. For this to work, add these two lines to `manifest.lua`:

  ```lua
    save_target = "sd",
    save_size   = 64,
  ```

- `math.randomseed(stat("frame"))` makes each game different. Pulli gives
  every game the same random numbers unless told otherwise, which makes
  games easy to test; seeding from the moment the player pressed A mixes
  them up.

## Step 8: sound and sparkle

```lua
-- step 8: sound and sparkle

local timer = require("timer")
local scene = require("scene")
local text = require("text")
local particles = require("particles")

local SPEED = 120
local BASKET, GEM, HEART, NO_HEART = 1, 3, 4, 5
local SFX_CATCH, SFX_MISS, SFX_OVER = 0, 1, 2      -- sfx/0-catch.wav and the rest

local basket_x
local gems = {}
local score, lives, gem_speed
local best = 0
local sparks = particles.new(60)
local SPARK = { speed = 60, life = 0.4, gravity = 200, colors = { 7, 10, 9 } }

local function drop_gem()
  gems[#gems + 1] = { x = math.random(4, 308), y = -8 }
end

local function caught(g)
  return g.y + 8 >= 218 and g.y <= 226
     and g.x + 8 >= basket_x and g.x <= basket_x + 16
end

local function draw_field()
  cls(1)
  for i = 1, #gems do spr(GEM, gems[i].x, gems[i].y) end
  spr(BASKET, basket_x, 220, 2, 1)
  sparks:draw()
  print("SCORE " .. score, 4, 4, 7)
  for i = 1, 3 do spr(i <= lives and HEART or NO_HEART, 286 + i * 9, 3) end
end

scene.add("title", {
  update = function(dt)
    if btnp("a") then
      math.randomseed(stat("frame"))
      scene.go("play")
    end
  end,
  draw = function()
    cls(1)
    text.shadow("CATCH", 140, 80, 10, 0)
    text.center("BEST " .. best, 110, 7)
    text.center("PRESS A", 150, 6)
  end,
})

scene.add("play", {
  enter = function()
    basket_x, score, lives, gem_speed = 144, 0, 3, 50
    gems = {}
    sparks:clear()
    timer.clear()
    timer.every(1.2, drop_gem)
  end,
  update = function(dt)
    timer.update(dt)
    sparks:update(dt)
    if btn("left") then basket_x = basket_x - SPEED * dt end
    if btn("right") then basket_x = basket_x + SPEED * dt end
    basket_x = math.max(0, math.min(320 - 16, basket_x))
    for i = #gems, 1, -1 do
      local g = gems[i]
      g.y = g.y + gem_speed * dt
      if caught(g) then
        table.remove(gems, i)
        score = score + 1
        gem_speed = gem_speed + 2
        sfx(SFX_CATCH)
        sparks:emit(g.x + 4, 220, 10, SPARK)
      elseif g.y > 240 then
        table.remove(gems, i)
        lives = lives - 1
        if lives == 0 then
          sfx(SFX_OVER)
          scene.go("over")
        else
          sfx(SFX_MISS)
        end
      end
    end
  end,
  draw = draw_field,
})

scene.add("over", {
  enter = function()
    if score > best then
      best = score
      save("best", best)
    end
  end,
  update = function(dt)
    sparks:update(dt)
    if btnp("a") then scene.go("title") end
  end,
  draw = function()
    draw_field()
    text.center("GAME OVER", 100, 8)
    text.center("PRESS A", 116, 7)
  end,
})

function init()
  best = load("best", 0)
  basket_x, score, lives = 144, 0, 3
  scene.go("title")
end

function update(dt) scene.update(dt) end
function draw() scene.draw() end
```

- `sfx(0)` plays the first file in the `sfx` folder, by name:
  `sfx/0-catch.wav`.
- `particles` is the helper for sparks, dust and smoke. `sparks:emit` sends
  out ten sparks; `sparks:update` and `sparks:draw` move and draw them.
  `SPARK` describes how they look and is made once, not on every catch.
- `text.shadow` draws the title with a dark copy behind it.

## Where next

- Swap the pictures: edit `sprites.png` in any paint program. See
  [Art and sound](art-and-sound.md) for the rules and the palette.
- Make it yours: a second kind of gem that is worth more, a bomb to avoid,
  a basket that speeds up.
- Look through [the helpers](helpers.md): `tween` makes things glide,
  `menu` makes an options screen, `dialog` lets characters talk.
- `examples/manickam` is a whole adventure: chapters drawn in Tiled,
  cut-scenes, night lit by lamps, mirror puzzles, saved progress, music,
  and every word in Tamil and English. Its
  [README](../../examples/manickam/README.md) explains every file.
