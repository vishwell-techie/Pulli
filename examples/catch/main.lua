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
