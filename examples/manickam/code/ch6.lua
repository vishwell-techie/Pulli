-- ch6.lua — Karthigai Deepam, the festival: the end of the game.
--
-- Kayalur at night. Paati asks Kayal to light the lamps; the light runs
-- from lamp to lamp through the village, two rows of clay lamps light up
-- along the street, the village comes out, and fireworks go up while the
-- credits rise, in whichever language the game is played in.
--
-- The heaviest scene in the game, on purpose: forty clay lamps and a crowd
-- of villagers as sprites, up to 128 sparks of fireworks at once, and the
-- whole map drawn in the darker half of the palette. The lamps and the
-- crowd are drawn from a few numbers each, not kept as tables, to leave
-- memory for the sparks.

local progress = require("progress")
local script   = require("script")
local core     = require("core")
local story    = require("story")
local fx       = require("fx")

local region = { map = "village.ooru", music = 8, night = true, no_hud = true }   -- festival music
local CROWD = 28
local lit, fireworks, roll, clock, credits = false, false, 0, 0, nil
local cx, cy = {}, {}                   -- where each line of the credits starts, worked out once
local rx, ry, rv = {}, {}, {}           -- rockets on their way up

-- four colours of firework, and a trail
for _, c in ipairs({ { 7, 10, 9, 8, 2 }, { 7, 12, 28, 1 }, { 7, 14, 8, 24 }, { 7, 11, 3, 35 }, { 10, 9, 4 } }) do
  fx.STYLES[#fx.STYLES + 1] = { speed = 60, vary = 0.4, gravity = 30, life = #c > 3 and 1.5 or 0.3, colors = c }
end
local BURSTS = #fx.STYLES - 4

function region.start(w)
  fx.reserve(128)
  for i = #w.slimes, 1, -1 do w.slimes[i] = nil end
  for _, l in ipairs(w.lamps) do l.beam = true end
  credits = core.wrap(story.t("credits"), 38)
  local y = 0
  for i, l in ipairs(credits) do
    cx[i], cy[i] = 160 - core.width(l) // 2, y
    y = y + core.height(l) + 4
  end
  lit, fireworks, roll, clock = false, false, 0, 0
  local p = w.p
  script.run(function(s)
    w.fade = 1
    s.fade(0, 1.5)
    w.card()
    s.wait(2)
    s.say("paati", "f_1")
    s.say("paati", "f_2")
    -- the light runs through the village, nearest lamps first
    progress.sfx(26)   -- chime
    table.sort(w.lamps, function(a, b) return math.abs(a.x - p.x) + math.abs(a.y - p.y) < math.abs(b.x - p.x) + math.abs(b.y - p.y) end)
    for _, l in ipairs(w.lamps) do
      w.light_lamp(l, true)
      progress.sfx(7)   -- lamp
      s.wait(0.25)
    end
    lit = true
    s.say("villager", "f_3")
    s.say("minmini", "f_4")
    if progress.data.lotuses >= 7 then s.say("paati", "f_lotus") end
    fireworks = true
    s.during(32, function(dt, k) roll = k end)
    s.wait(4)
    s.fade(1, 2)
  end, function()
    fx.release()
    w.finish()
  end)
end

function region.update(w, dt)
  if not fireworks then return end
  -- launch a rocket now and then; it bursts at the top of its climb
  clock = clock + dt
  if clock > 0.45 then
    clock = 0
    rx[#rx + 1], ry[#rx + 1], rv[#rx + 1] = w.cam.x + math.random(40, 280), w.cam.y + 240, -math.random(120, 170)
    progress.sfx(23)   -- launch
  end
  for i = #rx, 1, -1 do
    ry[i], rv[i] = ry[i] + rv[i] * dt, rv[i] + 70 * dt
    fx.burst(rx[i], ry[i], 1, BURSTS + 4, 0, 10)
    if rv[i] > -15 then
      fx.burst(rx[i], ry[i], 45, BURSTS + math.random(0, 3))
      progress.sfx(24)   -- boom
      table.remove(rx, i) table.remove(ry, i) table.remove(rv, i)
    end
  end
end

-- the clay lamps along the street, and the crowd walking up and down it
function region.draw(w)
  local f, left = stat("frame"), w.cam.x - 16
  for x = 24, 480, 24 do
    if x > left and x < left + 336 then for y = 154, 194, 40 do
      spr(940, x, y)
      if lit then pset(x + 3, y - 1 - (f + x) // 6 % 2, 10) end
    end end
  end
  if not lit then return end
  for i = 1, CROWD do
    local x = (40 + i * 97 + (i % 2 * 2 - 1) * f * 0.1) % 480
    if x > left and x < left + 336 then
      pal(14, i % 3 == 0 and 12 or 14)
      spr(i % 4 == 0 and 564 or 572 + f // 8 % 2 * 2, x, 160 + i * 13 % 22, 2, 2, i % 2 == 0)
    end
  end
  pal()
end

function region.draw_top(w)
  if roll <= 0 then return end
  camera()
  local top = 240 - roll * (240 + #credits * 14)
  for i, l in ipairs(credits) do
    local y = top + cy[i]
    if y > -24 and y < 240 then core.center(l, y, 7, 32, cx[i]) end
  end
  if roll > 0.95 then core.center(story.t("the_end"), 112, 10, 32) end
  camera(w.cam.x, w.cam.y)
end

return region
