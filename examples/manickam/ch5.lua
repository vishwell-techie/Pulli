-- ch5.lua — chapter 5, Kovil: up through the gopuram, then Irul.
--
-- The temple is one map of six floors stacked, the first at the bottom; the
-- camera shows one floor at a time. Each floor's way up is a door that
-- opens when the floor's lamps all burn. Some lamps sit behind rails where
-- only a beam of light can reach them, turned there by mirrors (A turns a
-- mirror). The last piece is on the top floor.
--
-- At the top Irul is coiled round the great lamp. Kayal does not fight it:
-- in three phases she dodges its dark orbs while lighting lamps: by hand,
-- then by turning mirrors, then by hand again after Irul has put them out.
-- Between phases they talk, and each phase leaves Irul smaller. An orb that
-- reaches lamplight is gone.

local progress = require("progress")
local script   = require("script")
local irul     = require("irul")
local fx       = require("fx")

local temple = { map = "temple.ooru", music = 6, pieces = { 7 }, floor_h = 240,   -- temple music
  lines = { hint = "c5_start", done = "c5_stairs", exit = "c5_stairs" } }
local top = { map = "top.ooru", music = 7 }   -- irul music
temple.top = top

-- ---- the temple floors -------------------------------------------------------------

function temple.start(w)
  for _, l in ipairs(w.lamps) do l.beam = l.cy % 30 == 4 end    -- the lamps behind rails
  w.card()
  w.tip("c5_start")
end

function temple.update(w, dt)
  local p = w.p
  local y0 = p.y // 240 * 30                        -- the top row of this floor
  local floor = 6 - y0 // 30
  w.dark = floor == 5
  if floor % 2 == 0 then w.tip("c5_mirror") end
  -- the floor's lamps all lit (and on the top floor, the piece found): the door opens
  local lit, all = 0, 0
  for _, l in ipairs(w.lamps) do
    if l.cy >= y0 and l.cy < y0 + 30 then all = all + 1; if l.lit then lit = lit + 1 end end
  end
  if map.get(0, 19, y0 + 4) == w.T.door then
    if lit == all and (floor < 6 or w.pieces_left() == 0) then
      map.set(0, 19, y0 + 4, w.T.door_open)
      map.set(0, 20, y0 + 4, w.T.door_open)
      progress.sfx(8)   -- door
      w.say("minmini", "c5_open")
    elseif p.y // 8 < y0 + 8 then
      w.tip("c5_stairs")
    end
  end
  -- the stairs: up to the next floor, or out on top
  if map.get(0, (p.x + 4) // 8, (p.y + 2) // 8) == 106 then
    if floor == 6 then
      w.start(5, top)
      return
    end
    for _, g in ipairs(w.marks.guide) do
      if g.cy < y0 and g.cy >= y0 - 30 then p.x, p.y = g.x - 4, g.y - 3 end
    end
    w.checkpoint.x, w.checkpoint.y = p.x, p.y
    w.cam.y = p.y - 120
    w.say("minmini", "c5_floor", floor + 1)
  end
end

function temple.hud(w)
  print(string.format("%d/6", 6 - w.p.y // 240), 222, 3, 7)
end

-- ---- the top: Irul -----------------------------------------------------------------

local MAX = 100
local ox, oy, vx, vy = {}, {}, {}, {}  -- the dark orbs
local n, phase, clock, angle, snake, lamp
local CX, CY = 160, 116                  -- the great lamp

local function orb(x, y, a, speed)
  if n < MAX then
    n = n + 1
    ox[n], oy[n], vx[n], vy[n] = x, y, math.cos(a) * speed, math.sin(a) * speed
  end
end

-- All the lamps lit by hand (beam false), or all those lit by beams.
local function lamps_lit(w, beam)
  for _, l in ipairs(w.lamps) do
    if l.beam == beam and not l.lit then return false end
  end
  return true
end

function top.start(w)
  n, phase, clock, angle = 0, 0, 0, 0
  for _, l in ipairs(w.lamps) do l.beam = l.cx == 3 or l.cx == 36 end   -- the four out of reach
  lamp = { x = CX, y = CY + 16, draw = function(a) spr(a.lit and 296 or 298, CX - 8, CY - 16, 2, 4) end }
  snake = irul.new(16, 4, CX, CY - 40)
  w.actors[1], w.actors[2] = lamp, { x = 0, y = 999, draw = function() snake:draw() end }
  script.run(function(s)
    s.say("irul", "b_1")
    s.say("kayal", "b_2")
    s.say("minmini", "b_tip1")
    phase = 1
  end)
end

-- Between the phases: the orbs fade, Irul and Kayal talk, Irul shrinks.
local function between(w, a, b, tip, after)
  phase = 0
  for i = 1, n do fx.burst(ox[i], oy[i], 2, fx.DARK) end
  n = 0
  script.run(function(s)
    s.tween(snake, "scale", snake.scale - 0.22, 1)
    s.say("irul", a)
    s.say("kayal", b)
    if after then after(s) end
    if tip then s.say("minmini", tip) end
  end)
end

function top.update(w, dt)
  local p = w.p
  -- Irul circles the great lamp, wider as it shrinks
  angle = angle + dt * (0.8 + phase * 0.25)
  local r = 70 - snake.scale * 20
  snake:go(CX + math.cos(angle) * r, CY - 10 + math.sin(angle) * r * 0.6)
  if phase == 0 then return end
  -- orbs, in a pattern for each phase
  clock = clock + dt
  if phase == 1 and clock > 2 then
    clock = 0
    for k = 0, 11 do orb(snake.x, snake.y, k * 0.5236 + angle, 45) end
    progress.sfx(22)   -- orb
  elseif phase == 2 and clock > 0.12 then
    clock = 0
    for k = 0, 2 do orb(snake.x, snake.y, angle * 3 + k * 2.094, 55) end
  elseif phase == 3 and clock > 1.4 then
    clock = 0
    for k = 0, 15 do orb(snake.x, snake.y, k * 0.3927 - angle, 50) end
    local a = math.atan(p.y - snake.y, p.x - snake.x)
    for k = -1, 1 do orb(snake.x, snake.y, a + k * 0.25, 80) end
    progress.sfx(22)   -- orb
  end
  local i = 1
  while i <= n do
    ox[i], oy[i] = ox[i] + vx[i] * dt, oy[i] + vy[i] * dt
    local gone = ox[i] < -8 or ox[i] > 328 or oy[i] < -8 or oy[i] > 248 or w.lamp_over(ox[i], oy[i])
    if not gone and math.abs(ox[i] - p.x - 4) < 6 and math.abs(oy[i] - p.y - 2) < 6 then
      w.hurt(ox[i], oy[i])
      gone = true
    end
    if gone then
      ox[i], oy[i], vx[i], vy[i] = ox[n], oy[n], vx[n], vy[n]
      n = n - 1
    else i = i + 1 end
  end
  -- the phases end when their lamps burn
  if phase == 1 and lamps_lit(w, false) then
    between(w, "b_3", "b_4", "b_tip2")
    phase = -2
  elseif phase == 2 and lamps_lit(w, true) then
    between(w, "b_5", "b_6", "b_tip3", function(s)
      -- Irul puts out the lamps by hand; the beams light their own again
      w.flash = 1
      progress.sfx(21)   -- hiss
      for _, l in ipairs(w.lamps) do
        if not l.beam then l.lit = false; map.set(0, l.cx, l.cy, w.T.lamp_off) end
      end
    end)
    phase = -3
  elseif phase == 3 and lamps_lit(w, false) then
    between(w, "b_7", "b_8", nil, function(s)
      -- calmed, Irul slides away under the hills, and the great lamp is lit
      s.during(2.5, function(dt, k) snake.scale = math.max(0.15, snake.scale - dt * 0.2) end)
      snake.show = false
      lamp.lit = true
      progress.sfx(2)   -- piece
      fx.burst(CX, CY - 14, 60, fx.GLOW)
      s.wait(2)
    end)
    phase = -4
  end
  if phase < 0 and not script.active() then
    if phase == -4 then w.finish() else phase = -phase end
  end
end

function top.draw_top(w)
  local f = stat("frame")
  for i = 1, n do spr(946, ox[i] - 4, oy[i] - 4) end
  if lamp.lit then circ(CX, CY - 14, 6 + f // 4 % 3, 10) end
end

return temple
