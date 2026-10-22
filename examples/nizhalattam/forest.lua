-- forest.lua — the Painted Forest's own shadows, added to shadows.lua's
-- kinds. rooms.lua requires it in the forest's rooms only, and lets the code
-- go when Komali leaves the story.
--
-- The vine-hand waits under the leaves as a sprout, which no blow can
-- reach. When Komali comes close it rises, shaking (the warning), grabs,
-- and holds him: A, Y or B shake him free sooner, and a blow that lands on
-- the hand lets him go. Then it rests, up and open to blows, and sinks back.
-- The leaf-moth flutters at Komali in a wavering line. The banyan wisp
-- drifts at him through trunks and walls; now and then it fades away
-- (untouchable, and harmless) and comes back somewhere nearer.

local shadows = require("shadows")
local move    = require("move")

local forest = { kinds = { "vine", "moth", "wisp" } }

local V = { hp = 16, reach = 28, rise = 14, grab = 10, hold = 40, rest = 70, wait = 50, n = 6, mai = { 1, 3 } }
local M = { hp = 4, touch = 4, speed = 0.7, sight = 110, mai = { 0, 1 } }
local W = { hp = 12, touch = 8, speed = 0.35, quick = 0.9, seen = 200, fade = 70, mai = { 2, 4 } }
forest.V, forest.M, forest.W = V, M, W

-- Sprites in actors.png (see art.py): the vine-hand rising, grabbing,
-- resting (16x24) and hidden (8x8); the moth's two frames (8x8); the wisp's
-- two (16x16).
local UP, GRAB, REST, SPROUT, MOTH, WISP = 1792, 1794, 1796, 1798, 1799, 1801

local function ink(n) return math.max(1, math.floor(n * shadows.soft + 0.5)) end

-- ---- the vine-hand ----
local vine = { mai = V.mai, fly = true }       -- it does not fall

local function tall(s, h) s.y, s.h = s.feet - h, h end

function vine.add(s)
  s.feet, s.x, s.w = s.y + s.h, s.x - 1, 12
  tall(s, 4)
  s.hp, s.state, s.t = V.hp, "hide", 0
end

function vine.update(s, body, k, dx)
  local st = s.state
  if st == "hide" then
    if s.t > 0 then s.t = s.t - 1
    elseif math.abs(dx) < V.reach and math.abs(k.y + k.h - s.feet) < 24 then s.state, s.t = "rise", V.rise end
  elseif st == "rise" then
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "grab", V.grab tall(s, 22) end
  elseif st == "grab" then
    s.t = s.t - 1
    if shadows.overlap(s.x, s.y, s.w, s.h, k) and body.hurt(ink(V.n), s.x + s.w / 2) then
      shadows.hits = shadows.hits + 1
      k.held, k.vx, k.vy = V.hold, 0, 0
      s.state = "hold"
    elseif s.t <= 0 then s.state, s.t = "rest", V.rest end
  elseif st == "hold" then
    if s.free then k.held, s.free = 0, false end
    if k.held <= 0 then s.state, s.t = "rest", V.rest end
  elseif st == "rest" then
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "hide", V.wait tall(s, 4) end
  elseif st == "reel" then                         -- tripped or stunned: it rests after
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "rest", V.rest end
  end
end

-- under the leaves it cannot be reached; rising, a blow stops it
function vine.strike(s, n, dir, heavy)
  if s.state == "hide" then return nil end
  if s.state == "hold" then s.free = true end
  if s.state == "rise" then s.state, s.t = "rest", V.rest tall(s, 22) end
  return "hit"
end

function vine.draw(s)
  local cx, st = math.floor(s.x + s.w / 2), s.state
  if st == "hide" or (st == "rise" and s.t > V.rise / 2) then
    spr(SPROUT, cx - 4 + (st == "rise" and stat("frame") % 4 < 2 and 1 or 0), s.feet - 8)
  else
    spr(st == "rise" and UP or (st == "grab" or st == "hold") and GRAB or REST, cx - 8, s.feet - 24, 2, 3, s.face < 0)
  end
end

-- ---- the leaf-moth ----
local moth = { mai = M.mai, fly = true }

function moth.add(s)
  s.x, s.y, s.w, s.h = s.x + 2, s.y + 14, 6, 6
  s.hp = M.hp
end

function moth.update(s, body, k, dx)
  local dy = k.y + k.h / 2 - (s.y + s.h / 2)
  if s.state == "reel" then
    s.t, s.vx, s.vy = s.t - 1, s.vx * 0.9, 0
    if s.t <= 0 then s.state = "walk" end
  elseif math.abs(dx) < M.sight and math.abs(dy) < 80 then
    s.face = dx < 0 and -1 or 1
    s.vx = s.face * M.speed
    s.vy = math.max(-0.6, math.min(0.6, dy * 0.03)) + math.sin(s.step * 0.15) * 0.8
  else
    s.vx, s.vy = 0, math.sin(s.step * 0.1) * 0.3
  end
  s.step = s.step + 1
  move.by(s, s.vx, s.vy)
  shadows.touch(s, body, M.touch)
end

function moth.strike(s, n, dir)
  s.state, s.t, s.vx = "reel", 14, dir * 2.5
  return "hit"
end

function moth.draw(s)
  spr(MOTH + stat("frame") // 4 % 2, math.floor(s.x) - 1, math.floor(s.y) - 1, 1, 1, s.face < 0)
end

-- ---- the banyan wisp ----
local wisp = { mai = W.mai, fly = true }

function wisp.add(s)
  s.x, s.y, s.w, s.h = s.x - 1, s.y + 8, 12, 12
  s.hp, s.t = W.hp, W.seen
end

function wisp.update(s, body, k, dx)
  local dy = k.y + k.h / 2 - (s.y + s.h / 2)
  local len = math.max(1, math.sqrt(dx * dx + dy * dy))
  s.t = s.t - 1
  if s.state == "reel" then
    s.vx, s.vy = s.vx * 0.9, s.vy * 0.9
    if s.t <= 0 then s.state, s.t = "walk", W.seen end
  else
    local v = s.state == "gone" and W.quick or W.speed
    s.vx, s.vy = dx / len * v, dy / len * v
    if s.t <= 0 then
      if s.state == "gone" then s.state, s.t = "walk", W.seen else s.state, s.t = "gone", W.fade end
    end
  end
  s.face = dx < 0 and -1 or 1
  s.x, s.y = s.x + s.vx, s.y + s.vy                 -- through trunks and walls alike
  if s.state ~= "gone" then shadows.touch(s, body, W.touch) end
end

function wisp.strike(s, n, dir)
  if s.state == "gone" then return nil end
  s.state, s.t, s.vx, s.vy = "reel", 12, dir * 2, -0.5
  return "hit"
end

function wisp.draw(s)
  local f = stat("frame")
  -- fading out and back in, it flickers; gone, nothing shows
  if s.state == "gone" and (s.t > 12 and s.t < W.fade - 12 or f % 4 < 2) then return end
  spr(WISP + f // 10 % 2 * 2, math.floor(s.x) - 2, math.floor(s.y) - 2, 2, 2, s.face < 0)
end

shadows.kinds.vine, shadows.kinds.moth, shadows.kinds.wisp = vine, moth, wisp

return forest
