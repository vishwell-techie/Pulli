# பயிற்சி: Catch

**English:** [tutorial.md](../tutorial.md)

இந்தப் பயிற்சியில் நீங்கள் **Catch** விளையாட்டை உருவாக்குகிறீர்கள்: வானத்திலிருந்து
மணிகள் விழுகின்றன, நீங்கள் ஒரு கூடையை நகர்த்தி அவற்றைப் பிடிக்கிறீர்கள். மூன்று
தவறவிட்டால் விளையாட்டு முடிந்தது. முடிவில் அதில் படங்கள், ஒரு தலைப்புத் திரை,
சேமிக்கப்பட்ட சிறந்த மதிப்பெண், ஒலி, தீப்பொறிகள் இருக்கும்.

கீழே உள்ள ஒவ்வொரு படியும் அந்த நேரத்தில் முழு `main.lua` ஆகும்; அதனால் அதை
அப்படியே நகலெடுத்து ஓட்டலாம். ஒவ்வொன்றுக்கும் பின் உள்ள குறிப்புகளைப்
படியுங்கள்: புதிதாக என்ன வந்திருக்கிறது என்று அவை விளக்குகின்றன. முடிந்த
விளையாட்டு `examples/catch`-இல் இருக்கிறது. நிரலில் உள்ள குறிப்புகள்
ஆங்கிலத்தில் உள்ளன; அவை சொல்வதைக் கீழே உள்ள குறிப்புகள் தமிழில் விளக்குகின்றன.

## தொடங்கும் முன்

விளையாட்டின் கோப்புறையை உருவாக்கி, பயிற்சி பயன்படுத்தும் படங்களையும் ஒலிகளையும்
நகலெடுங்கள்:

```bash
python3 tools/pulli.py new catch
cp examples/catch/sprites.png catch/
cp -r examples/catch/sfx catch/
```

ஒவ்வொரு படிக்குப் பிறகும் `python3 tools/pulli.py run catch` மூலம் ஓட்டிப்
பாருங்கள்.

## படி 1: திரையில் ஏதாவது

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

- `init`, `update`, `draw` ஆகிய மூன்று ஃபங்ஷன்களும் ஒவ்வொரு விளையாட்டிலும்
  இருக்கும். இப்போதைக்கு `draw` மட்டுமே ஏதாவது செய்கிறது.
- `cls(1)` திரையை நிறம் 1-ஆல் (அடர் நீலம்) நிரப்புகிறது. நிறங்கள் 0 முதல் 63
  வரையிலான எண்கள்; [ஓவியமும் ஒலியும்](art-and-sound.md) அனைத்தையும் காட்டுகிறது.
- `print(text, x, y, colour)` எழுத்துகளை எழுதுகிறது; இங்கே x = 140, y = 40-இல்,
  வெள்ளையில். ஒவ்வொரு எழுத்தும் 8 பிக்சல் அகலம்.
- `rectfill(x, y, width, height, colour)` நிரப்பப்பட்ட பெட்டியை வரைகிறது. இங்கே
  அதுதான் கூடை: 32 அகலம், 8 உயரம் கொண்ட பழுப்புப் பெட்டி.

## படி 2: கூடையை நகர்த்துதல்

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

- இடது பொத்தான் அழுத்தப்பட்டிருக்கும் வரை `btn("left")` true ஆக இருக்கும்.
- கூடை ஒவ்வொரு ஃப்ரேமிலும் `SPEED * dt` நகர்கிறது: நொடிக்கு 120 பிக்சல்.
- `math.max`, `math.min` அதைத் திரைக்குள் வைத்திருக்கின்றன. திரை 320 அகலம், கூடை
  32, அதனால் அதன் இடது விளிம்பு 0 முதல் 288 வரை இருக்க வேண்டும்.

## படி 3: விழும் ஒரு மணி

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

- `local function` இந்தக் கோப்பு மட்டுமே பார்க்கக்கூடிய ஒரு ஃபங்ஷனை
  உருவாக்குகிறது. ஒவ்வொரு வேலைக்கும் தனிச் சிறிய ஃபங்ஷன் கொடுத்தால்
  விளையாட்டு படிக்க எளிதாக இருக்கும். `drop_gem` மணியை மேலே, புதிய இடத்தில்
  திரும்ப வைக்கிறது.
- `math.random(8, 312)` 8 முதல் 312 வரை ஒரு முழு எண்ணைத் தேர்ந்தெடுக்கிறது.
- மணி திரையின் அடியைத் தாண்டி விழுந்தால் மீண்டும் மேலிருந்து தொடங்குகிறது.
  `circfill` 4 ஆரம் கொண்ட மஞ்சள் வட்டத்தை வரைகிறது.

## படி 4: பிடித்து மதிப்பெண் பெறுதல்

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

- `caught()` மணி கூடையின் பெட்டிக்குள் இருக்கிறதா என்று பார்க்கிறது. இரண்டு
  பொருட்கள் தொடுகின்றன என்று பெரும்பாலான விளையாட்டுகள் இப்படித்தான்
  முடிவு செய்கின்றன.
- `..` உரைகளை இணைக்கிறது: `"SCORE " .. score` என்பது `"SCORE 3"` ஆகிறது.
- ஒவ்வொரு பிடிப்பும் மணியைச் சற்று வேகமாக விழச் செய்கிறது.

## படி 5: வடிவங்களுக்குப் பதிலாகப் படங்கள்

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

- `sprites.png` என்பது 8 × 8 படங்களின் கட்டம். `spr(3, x, y)` மேல் இடதில் 0 முதல்
  எண்ணி, 3-ஆம் எண் படத்தை வரைகிறது. அவற்றைப் பார்க்க `sprites.png`-ஐ ஒரு
  ஓவிய நிரலில் திறங்கள். `BASKET`, `GEM` என்பவை sprites.png-இல் அவற்றின் எண்கள்.
- கூடை அருகருகே உள்ள இரண்டு படங்கள், அதனால் அது `spr(1, x, y, 2, 1)` மூலம்
  வரையப்படுகிறது: இரண்டு கட்டம் அகலம், ஒன்று உயரம்.
- இப்போது கூடை 16 பிக்சல் அகலம், அதனால் விளிம்புகளும் பிடிப்புப் பெட்டியும்
  அதற்கு ஏற்ப மாறுகின்றன.

## படி 6: பல மணிகள், மூன்று உயிர்கள்

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

- `require("timer")` Pulli-யின் தயார் உதவி நிரல்களில் ஒன்றை ஏற்றுகிறது. நிறுவ
  எதுவும் இல்லை: விளையாட்டைப் பேக் செய்யும்போது உதவி நிரல் உள்ளே
  சேர்க்கப்படுகிறது. `timer.every` ஒவ்வொரு 1.2 நொடிக்கும் `drop_gem`-ஐ
  அழைக்கிறது; `timer.update(dt)` அதை ஓட வைக்கிறது.
- `gems` என்பது டேபிள்களின் டேபிள். ஒவ்வொரு மணியும் `{ x = ..., y = ... }`;
  `#gems` எத்தனை உள்ளன என்று சொல்கிறது.
- லூப் கடைசி மணியிலிருந்து முதலாவது வரை பின்னோக்கிச் செல்கிறது; அதனால்
  `table.remove` மூலம் ஒன்றை நீக்கும்போது அடுத்தது ஒருபோதும் தவறாது.
- A அழுத்தப்படும் ஃப்ரேமில் `btnp("a")` true ஆகும். இங்கே அது விளையாட்டை
  மீண்டும் தொடங்குகிறது.

## படி 7: ஒரு தலைப்புத் திரை, சிறந்த மதிப்பெண் சேமிப்பு

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

- `scene` இன்னொரு உதவி நிரல். விளையாட்டின் ஒவ்வொரு திரையும் தனக்கென
  `update`, `draw` கொண்ட ஒரு டேபிள்; திரை தொடங்கும்போது `enter` ஓடும்.
  `scene.go("play")` திரையை மாற்றுகிறது.
- `text` உதவி நிரலின் `text.center` ஒரு வரியைத் திரையின் நடுவில் வைக்கிறது.
- `save("best", best)` சிறந்த மதிப்பெண்ணை அடுத்த முறைக்காகச் சேமிக்கிறது;
  `load("best", 0)` அதைத் திரும்பப் படிக்கிறது (முதல் முறை 0). இது வேலை செய்ய,
  `manifest.lua`-இல் இந்த இரண்டு வரிகளைச் சேர்க்கவும்:

  ```lua
    save_target = "sd",
    save_size   = 64,
  ```

- `math.randomseed(stat("frame"))` ஒவ்வொரு விளையாட்டையும் வேறுபடுத்துகிறது.
  வேறு விதமாகச் சொல்லாவிட்டால் Pulli ஒவ்வொரு விளையாட்டுக்கும் ஒரே சீரற்ற
  எண்களைத் தருகிறது, இது விளையாட்டுகளைச் சோதிப்பதை எளிதாக்குகிறது; வீரர் A
  அழுத்திய நொடியிலிருந்து விதை எடுப்பது அவற்றைக் கலக்கிறது.

## படி 8: ஒலியும் மினுமினுப்பும்

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

- `sfx(0)` `sfx` கோப்புறையில் பெயர் வரிசைப்படி முதல் கோப்பை இசைக்கிறது:
  `sfx/0-catch.wav`.
- `particles` தீப்பொறி, தூசி, புகைக்கான உதவி நிரல். `sparks:emit` பத்து
  தீப்பொறிகளை அனுப்புகிறது; `sparks:update`, `sparks:draw` அவற்றை நகர்த்தி
  வரைகின்றன. `SPARK` அவை எப்படித் தோன்ற வேண்டும் என்று சொல்கிறது; அது ஒவ்வொரு
  பிடிப்பிலும் அல்ல, ஒரு முறை மட்டுமே உருவாக்கப்படுகிறது.
- `text.shadow` தலைப்பை அதன் பின்னால் ஒரு இருண்ட நகலுடன் வரைகிறது.

## அடுத்து எங்கே

- படங்களை மாற்றுங்கள்: எந்த ஓவிய நிரலிலும் `sprites.png`-ஐத் திருத்துங்கள்.
  விதிகளுக்கும் வண்ணத்தட்டுக்கும் [ஓவியமும் ஒலியும்](art-and-sound.md) பாருங்கள்.
- உங்களுடையதாக்குங்கள்: அதிக மதிப்புள்ள இரண்டாம் வகை மணி, தவிர்க்க வேண்டிய
  ஒரு வெடிகுண்டு, வேகம் கூடும் கூடை.
- [உதவி நிரல்களைப்](helpers.md) பாருங்கள்: `tween` பொருட்களை வழுக்கிச் செல்ல
  வைக்கிறது, `menu` ஒரு அமைப்புத் திரையை உருவாக்குகிறது, `dialog` கதாபாத்திரங்களைப்
  பேச வைக்கிறது.
- `examples/manickam` வரைபடங்கள், எதிரிகள், தண்ணீர், நிலைகள், இசை கொண்ட
  பெரிய விளையாட்டு.
