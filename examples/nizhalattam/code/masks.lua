-- masks.lua — the Market of Masks' own shadows, added to shadows.lua's
-- kinds. rooms.lua requires it in the market's rooms only, and lets the
-- code go when Komali leaves the story.
--
-- The mask thief runs at Komali and, touching him, snatches up to 20 of his
-- mai and runs off with it; cornered, it cowers. Caught and torn, it gives
-- back twice what it took. It does not hurt.
-- The juggler stands on its perch (an awning, a stall's roof), juggling
-- (the warning: balls in the air over its head), then throws three knives
-- in arcs, to fall about Komali. Struck while juggling, it drops them.
-- Twin masks float at Komali from either side, the sun and the moon. Every
-- few seconds both flash (the warning) and swap places. Tear one, and the
-- other flies at him faster, and swaps no more.

local shadows = require("shadows")
local fight   = require("fight")
local komali  = require("body")
local move    = require("move")
local fx      = require("fx")
local C       = require("colours")

local masks = { kinds = { "thief", "juggler", "twin" } }

local TH = { hp = 8, speed = 1.2, flee = 2.2, steal = 20, sight = 150, mai = { 1, 2 } }
local JG = { hp = 18, sight = 200, every = 110, wind = 26, knives = 3, n = 8, g = 0.12, spread = 18,
             life = 150, mai = { 2, 4 } }
local TW = { hp = 14, speed = 0.6, rage = 1.0, touch = 8, every = 150, wind = 20, mai = { 2, 3 } }
masks.TH, masks.JG, masks.TW = TH, JG, TW

-- Sprites in actors.png (see art.py): the thief running (two) and caught
-- (16x24); the juggler juggling, throwing (24x32); the sun mask and the
-- moon mask (16x16).
local THIEF, JUGGLE, THROW, SUN = 632, 828, 1596, 1926

local function ink(n) return math.max(1, math.floor(n * shadows.soft + 0.5)) end
local function flash(s) if s.state == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.cloth, C.glow) pal(C.vermil, C.glow)
  pal(C.marigold, C.glow) pal(C.silver, C.glow) end end

-- ---- the mask thief ----
local thief = { mai = TH.mai }

function thief.add(s)
  s.y, s.h, s.stolen = s.y + 2, 18, 0
  s.hp = TH.hp
end

function thief.update(s, body, k, dx)
  local st = s.state
  if st == "reel" then
    s.t, s.vx = s.t - 1, s.vx * 0.8
    if s.t <= 0 then s.state = s.stolen > 0 and "flee" or "walk" end
    return
  end
  if st == "walk" then                             -- at him, for his mai
    if math.abs(dx) < TH.sight and math.abs(k.y - s.y) < 40 then
      s.face = dx < 0 and -1 or 1
      local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
      s.vx = move.blocked(ahead, s.y + s.h, 1, 1) and s.face * TH.speed or 0
      if shadows.overlap(s.x, s.y, s.w, s.h, k) and fight.mai > 0 and k == komali.k then   -- (not a decoy)
        local n = math.min(TH.steal, fight.mai)
        fight.mai, s.stolen, s.state = fight.mai - n, n, "flee"
        fx.spark(s.x + s.w / 2, s.y + 4)
      end
    else
      s.vx = 0
    end
  elseif st == "flee" then                         -- away from him, as fast as it can
    s.face = dx < 0 and 1 or -1
    local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
    if move.blocked(ahead, s.y, 1, s.h - 2) or not move.blocked(ahead, s.y + s.h, 1, 1) then
      s.state, s.vx = "cower", 0
    else
      s.vx = s.face * TH.flee
    end
  else                                             -- cornered
    s.vx = 0
    if math.abs(dx) > 120 then s.state = "flee" end
  end
end

function thief.strike(s, n, dir)
  s.state, s.t, s.vx = "reel", 10, dir * 1.5
  return "hit"
end

-- caught: twice what it took
function thief.torn(s)
  if s.stolen > 0 then
    fight.mai = fight.mai + s.stolen * 2
    fx.tear(s.x + s.w / 2, s.y, 0)
  end
end

function thief.draw(s)
  local n = s.state == "cower" and 2 or (math.abs(s.vx) > 0.1 and s.step // 6 % 2 or 0)
  spr(THIEF + n * 2, math.floor(s.x) - 3, math.floor(s.y) - 6, 2, 3, s.face < 0)
end

-- ---- the juggler, and its knives (a few long arrays, shared) ----
local juggler = { mai = JG.mai, fly = true }     -- (it stays on its perch)
local KN = 9
local kx, ky, kvx, kvy, kl = {}, {}, {}, {}, {}
for n = 1, KN do kx[n], ky[n], kvx[n], kvy[n], kl[n] = 0, 0, 0, 0, 0 end
local moved, drawn = -1, -1                        -- the frame the knives last moved, were drawn

function juggler.add(s)
  s.hp, s.t = JG.hp, JG.every // 2
  for n = 1, KN do kl[n] = 0 end
end

local function throw(s, k)
  -- three knives, each lobbed to fall a little apart about him
  local x0, y0 = s.x + s.w / 2 + s.face * 6, s.y - 2
  for a = -1, 1 do
    for n = 1, KN do
      if kl[n] <= 0 then
        local tx, ty = k.x + k.w / 2 + a * JG.spread, k.y + k.h / 2
        local T = 44 + a * 6                       -- frames in the air
        kx[n], ky[n], kl[n] = x0, y0, JG.life
        kvx[n] = (tx - x0) / T
        kvy[n] = (ty - y0) / T - JG.g * T / 2
        break
      end
    end
  end
end

local function knives(body, k)
  if moved == stat("frame") then return end
  moved = stat("frame")
  for n = 1, KN do
    if kl[n] > 0 then
      kl[n], kvy[n] = kl[n] - 1, kvy[n] + JG.g
      kx[n], ky[n] = kx[n] + kvx[n], ky[n] + kvy[n]
      if move.blocked(kx[n], ky[n], 1, 1) then
        kl[n] = math.min(kl[n], 20)                -- stuck in the ground a moment
        kvx[n], kvy[n] = 0, 0
      elseif kvx[n] ~= 0 and kx[n] >= k.x and kx[n] < k.x + k.w and ky[n] >= k.y and ky[n] < k.y + k.h then
        if body.hurt(ink(JG.n), kx[n] - kvx[n]) then shadows.hits = shadows.hits + 1 end
        kl[n] = 0
      end
    end
  end
end

function juggler.update(s, body, k, dx)
  knives(body, k)
  local st, dist = s.state, math.abs(dx)
  local seen = dist < JG.sight and math.abs(k.y - s.y) < 80
  if seen then s.face = dx < 0 and -1 or 1 end
  s.vx = 0
  if st == "walk" or st == "rest" then
    s.t = s.t - 1
    if s.t <= 0 and seen then s.state, s.t, s.vx = "wind", JG.wind, 0 end
  elseif st == "wind" then
    s.t = s.t - 1
    if s.t <= 0 then throw(s, k) s.state, s.t = "rest", JG.every end
  else                                             -- reeling
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "rest", JG.every // 2 end
  end
end

function juggler.strike(s, n, dir)
  if s.state == "wind" then s.state, s.t = "reel", 16 end      -- the balls dropped
  return "hit"
end

function juggler.draw(s)
  local f = stat("frame")
  flash(s)
  spr(s.state == "rest" and s.t > JG.every - 12 and THROW or JUGGLE, math.floor(s.x) - 7, math.floor(s.y) - 12,
      3, 4, s.face < 0)
  pal()
  if s.state == "wind" then                        -- the balls in the air over its head
    for b = 0, 2 do
      local a = f * 0.2 + b * 2.09
      circfill(s.x + s.w / 2 + math.cos(a) * 6, s.y - 10 + math.sin(a) * 4, 1, b == 0 and C.vermil or b == 1 and C.lamp or C.sky)
    end
  end
  if drawn ~= f then                               -- the knives, once a frame
    drawn = f
    for n = 1, KN do
      if kl[n] > 0 then
        local a = kvx[n] == 0 and 1.2 or f * 0.5 + n
        local cx, cy = math.cos(a) * 3, math.sin(a) * 3
        line(kx[n] - cx, ky[n] - cy, kx[n] + cx, ky[n] + cy, C.silver)
        pset(kx[n] - cx, ky[n] - cy, C.wood)
      end
    end
  end
end

-- ---- twin masks ----
local twin = { mai = TW.mai, fly = true }
local making = false

function twin.add(s)
  s.x, s.y, s.w, s.h = s.x - 1, s.y + 4, 12, 12
  s.hp, s.t, s.sun = TW.hp, TW.every, true
  if not making then                              -- the moon, its twin, a little way off
    making = true
    local m = shadows.add(s.x + 1 + 5 + 48, s.y - 4 + 20, "twin")
    making = false
    m.sun, s.twin, m.twin = false, m, s
  end
end

function twin.update(s, body, k, dx)
  local o = s.twin
  local alone = not (o and o.on)
  local dy = k.y + 4 - s.y
  if s.state == "reel" then
    s.t = s.t - 1
    s.vx, s.vy = s.vx * 0.9, s.vy * 0.9
    if s.t <= 0 then s.state, s.t = "walk", TW.every end
  else
    local len = math.max(1, math.sqrt(dx * dx + dy * dy))
    local v = alone and TW.rage or TW.speed
    s.vx, s.vy = dx / len * v, dy / len * v
    s.face = dx < 0 and -1 or 1
    if not alone and s.sun then                   -- the sun keeps the time for both
      s.t = s.t - 1
      if s.t == TW.wind then s.state, o.state, o.t = "wind", "wind", TW.wind end
      if s.t <= 0 then                             -- they swap places
        s.x, o.x, s.y, o.y = o.x, s.x, o.y, s.y
        fx.spark(s.x + 6, s.y + 6)
        fx.spark(o.x + 6, o.y + 6)
        s.state, o.state, s.t = "walk", "walk", TW.every
      end
    elseif s.state == "wind" then
      s.t = s.t - 1
    end
  end
  s.x, s.y = s.x + s.vx, s.y + s.vy
  shadows.touch(s, body, TW.touch)
end

function twin.strike(s, n, dir)
  if s.state ~= "wind" then s.state, s.t = "reel", 12 end
  s.vx = dir * 2
  return "hit"
end

function twin.draw(s)
  flash(s)
  local bob = math.sin((stat("frame") + (s.sun and 0 or 20)) * 0.1) * 1.5
  spr(SUN + (s.sun and 0 or 2), math.floor(s.x) - 2, math.floor(s.y + bob) - 2, 2, 2, s.face < 0)
  pal()
end

shadows.kinds.thief, shadows.kinds.juggler, shadows.kinds.twin = thief, juggler, twin

return masks
