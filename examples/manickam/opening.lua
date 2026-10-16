-- opening.lua — the opening cut-scene, in the temple hall on the night
-- before the festival: the lamps go out, Irul rises from the temple tank,
-- coils round the ruby and shatters it, and Minmini appears.
--
-- A region like the chapters (see world.lua), but one the player only
-- watches. START skips it.

local script   = require("script")
local fx       = require("fx")
local irul     = require("irul")
local progress = require("progress")
local core     = require("core")

local RX, RY = 160, 34                  -- the ruby
local region = { map = "hall.ooru", music = 6, no_hud = true }   -- temple music
local snake, whole, pieces

-- The ruby, its seven pieces flying, and Irul: drawn over everyone.
local function draw()
  local f = stat("frame")
  if whole then
    circfill(RX, RY, 10 + f // 8 % 3, 24)
    circfill(RX, RY, 7 + f // 6 % 2, 8)
    spr(698, RX - 8, RY - 9, 2, 2)
  end
  for i = 1, #pieces, 4 do spr(944, pieces[i] - 4, pieces[i + 1] - 4) end
  snake:draw()
end

-- Irul's head goes round the ruby, `turns` radians in t seconds, closing
-- from radius r0 to r1.
local function coil(s, t, a0, turns, r0, r1)
  s.during(t, function(dt, k)
    local a, r = a0 + k * turns, r0 + (r1 - r0) * k
    snake:go(RX + math.cos(a) * r, RY + 4 + math.sin(a) * r * 0.7)
    if r1 < r0 and math.random() < 0.5 then fx.burst(RX, RY, 1, fx.RUBY) end
  end)
end

function region.start(w)
  local kayal, paati, m = w.p, w.npcs[1], w.marks.irul[1]
  w.freeze, w.mm.hide, kayal.face, paati.face = true, true, "up", "left"
  snake = irul.new(14, 5, m.x, m.y + 8)
  snake.show, whole, pieces = false, true, {}
  w.actors[1] = { x = 0, y = 999, draw = draw }

  script.run(function(s)
    w.fade = 1
    s.fade(0, 1.5)
    s.say("paati", "pro_1")
    s.say("kayal", "pro_2")
    s.say("paati", "pro_3")

    -- the wind, and the lamps going out one by one
    progress.music(9, 1500)   -- shadow music
    progress.sfx(20)   -- wind
    w.shake(1, 1.5)
    for i, l in ipairs(w.lamps) do
      s.wait(0.25)
      map.set(0, l.cx, l.cy, w.T.lamp_off)
      fx.burst(l.x, l.y - 4, 8, fx.DUST)
      w.fade = i * 0.06
    end
    kayal.face = "down"
    s.say("kayal", "pro_4")

    -- Irul rises out of the tank and slides up the hall to the ruby
    progress.sfx(12)   -- splash
    fx.burst(snake.x, snake.y, 30, fx.SPLASH)
    snake.show = true
    progress.sfx(21)   -- hiss
    local y0 = snake.y
    s.during(3, function(dt, k)
      snake:go(RX + math.sin(k * 14) * 18 * (1 - k), y0 + (RY + 26 - y0) * k)
    end)
    coil(s, 2, 1.57, 9, 26, 26)
    s.say("irul", "pro_5")
    kayal.face = "up"
    s.say("kayal", "pro_6")

    -- the coils tighten, and the ruby shatters into seven
    progress.sfx(27)   -- rumble
    coil(s, 1.4, 10.57, 14, 26, 12)
    w.shake(4, 0.8)
    progress.sfx(19)   -- shatter
    w.flash, whole = 1, false
    for i = 0, 6 do
      local a = i * 0.8976 + 0.3
      pieces[i * 4 + 1], pieces[i * 4 + 2], pieces[i * 4 + 3], pieces[i * 4 + 4] = RX, RY, math.cos(a) * 150, math.sin(a) * 110 - 30
    end
    fx.burst(RX, RY, 60, fx.RUBY)
    s.during(1.8, function(dt)
      for i = 1, #pieces, 4 do
        pieces[i], pieces[i + 1] = pieces[i] + pieces[i + 2] * dt, pieces[i + 1] + pieces[i + 3] * dt
      end
    end)
    for i = #pieces, 1, -1 do pieces[i] = nil end

    -- Irul sinks back into the dark, and slimes come up out of the water
    local sx, sy = snake.x, snake.y
    s.during(2.2, function(dt, k) snake:go(sx + math.sin(k * 10) * 16, sy + (y0 + 10 - sy) * k) end)
    snake.show = false
    s.fade(0.55, 0.8)
    progress.sfx(12)   -- splash
    for i = 1, 3 do w.add_slime(96 + i * 32, 186 + i % 2 * 6) end
    paati.face = "down"
    s.say("paati", "pro_7")

    -- a small light
    w.mm.x, w.mm.y, w.mm.hide = kayal.x + 24, kayal.y - 30, false
    fx.burst(w.mm.x, w.mm.y, 30, fx.GLOW)
    progress.sfx(26)   -- chime
    for _, sl in ipairs(w.slimes) do sl.shrunk = 99 end
    s.fade(0.25, 1)
    s.say("minmini", "pro_8")
    s.say("minmini", "pro_9")
    paati.face = "left"
    s.say("paati", "pro_10")
    s.fade(1, 1.2)
  end, function()
    progress.data.seen.opening = true
    progress.save()
    core.through(1.2, function() core.go("play", 0) end)
  end)
end

return region
