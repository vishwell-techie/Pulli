-- palace.lua — the Lamp Palace's own shadows, added to shadows.lua's kinds.
-- rooms.lua requires it in the palace's rooms only, and lets the code go
-- when Komali leaves the story.
--
-- The lamp guard holds its shield to the front, so a light blow from the
-- front is turned aside; close, it draws back its spear (the warning) and
-- thrusts, further than a sword reaches, then rests, open to blows.
-- The mirror shade is Komali's own shadow: it watches what he does, and a
-- moment later does it too, at him: his jump, his blow, his roll.
-- The cinder drifts at Komali; close, it swells and flashes (the warning)
-- and bursts, burning all round it, shadows too. Struck, it bursts soon.

local shadows = require("shadows")
local fight   = require("fight")
local move    = require("move")
local fx      = require("fx")
local C       = require("colours")

local palace = { kinds = { "lampguard", "mirror", "cinder" } }

local LG = { hp = 44, speed = 0.55, sight = 130, reach = 34, wind = 26, thrust = 8, rest = 46, n = 12, mai = { 3, 6 } }
local MR = { hp = 24, keep = 56, speed = 1.0, delay = 24, n = 10, touch = 8, mai = { 3, 5 } }
local CN = { hp = 6, speed = 0.5, near = 40, fuse = 36, struck = 8, r = 30, n = 14, hurts = 10, mai = { 1, 2 } }
palace.LG, palace.MR, palace.CN = LG, MR, CN

-- Sprites in actors.png (see art.py): the lamp guard on guard and
-- thrusting (24x32). The mirror shade wears Komali's own frames, in ink.
local GUARD, THRUST = 1084, 1340

local function ink(n) return math.max(1, math.floor(n * shadows.soft + 0.5)) end

-- ---- the lamp guard ----
local guard = { mai = LG.mai }

function guard.add(s) s.hp = LG.hp end

function guard.update(s, body, k, dx)
  local st = s.state
  if st == "walk" then
    if math.abs(dx) < LG.sight and math.abs(k.y - s.y) < 40 then
      s.face = dx < 0 and -1 or 1
      if math.abs(dx) > LG.reach then
        local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
        s.vx = move.blocked(ahead, s.y + s.h, 1, 1) and s.face * LG.speed or 0
      else
        s.vx, s.state, s.t = 0, "wind", LG.wind
      end
    else
      s.vx = 0
    end
  elseif st == "wind" then
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t, s.landed = "strike", LG.thrust, false end
  elseif st == "strike" then
    local bx = s.face > 0 and s.x + s.w or s.x - 30
    if not s.landed and shadows.overlap(bx, s.y + 6, 30, 8, k) and body.hurt(ink(LG.n), s.x + s.w / 2) then
      s.landed = true
      shadows.hits = shadows.hits + 1
    end
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "rest", LG.rest end
  else
    s.vx, s.t = s.vx * 0.85, s.t - 1
    if s.t <= 0 then s.state = "walk" end
  end
end

-- the shield turns a light blow from the front, unless it is resting
function guard.strike(s, n, dir, heavy)
  if not heavy and dir == -s.face and (s.state == "walk" or s.state == "wind") then
    fx.spark(s.x + s.w / 2 + s.face * 8, s.y + 8)
    s.vx = -s.face * 0.8
    return "blocked"
  end
  if heavy or s.state == "walk" then s.state, s.t = "reel", heavy and 24 or 12 end
  s.vx = dir * (heavy and 2.5 or 1.2)
  return "hit"
end

function guard.draw(s)
  if s.state == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.silver, C.glow) pal(C.marigold, C.glow) end
  spr(s.state == "strike" and THRUST or GUARD, math.floor(s.x) - 7, math.floor(s.y) - 12, 3, 4, s.face < 0)
  pal()
end

-- ---- the mirror shade ----
local mirror = { mai = MR.mai }
local komali = require("body").k
local seen_swing, seen_dodge, seen_vy = 0, 0, 0    -- what Komali was doing, as the shades last saw
local seen_at, seen = -1, nil                      -- the frame they last looked, and what he did then

function mirror.add(s)
  s.hp, s.copy, s.t, s.jumped = MR.hp, nil, 0, false
  seen_swing = fight.swing
end

-- what Komali did this frame, if anything: a jump, a blow, a roll (looked
-- at once a frame, for all the shades)
local function did(k)
  if seen_at == stat("frame") then return seen end
  seen_at, seen = stat("frame"), nil
  if fight.swing ~= seen_swing then seen = "strike"
  elseif k.dodge > 0 and seen_dodge == 0 then seen = "dodge"
  elseif k.vy < -3 and seen_vy >= -3 then seen = "jump" end
  seen_swing, seen_dodge, seen_vy = fight.swing, k.dodge, k.vy
  return seen
end

function mirror.update(s, body, k, dx)
  local act = did(komali)
  if act and not s.copy then s.copy, s.t = act, MR.delay end
  local st = s.state
  s.face = dx < 0 and -1 or 1
  if st == "walk" then                             -- keeps a little way off, watching
    local dist, go = math.abs(dx), 0
    if dist > MR.keep + 16 then go = s.face elseif dist < MR.keep - 16 then go = -s.face end
    local ahead = go > 0 and s.x + s.w + 1 or s.x - 2
    s.vx = (go ~= 0 and move.blocked(ahead, s.y + s.h, 1, 1)) and go * MR.speed or 0
    if s.copy then
      s.t = s.t - 1
      if s.t <= 0 then                             -- now it does the same, at him
        s.state, s.t, s.landed = s.copy, s.copy == "dodge" and 18 or s.copy == "strike" and 14 or 40, false
        s.copy = nil
        if s.state == "jump" then s.vy, s.vx = -3.7, s.face * 1.6 end
      end
    end
  elseif st == "strike" then                       -- a lunge and a blow
    s.vx = s.t > 8 and s.face * 3 or 0
    if s.t <= 8 and s.t > 4 then
      if not s.landed and shadows.overlap(s.face > 0 and s.x + s.w or s.x - 18, s.y, 18, s.h, k)
         and body.hurt(ink(MR.n), s.x + s.w / 2) then
        s.landed = true
        shadows.hits = shadows.hits + 1
      end
    end
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "rest", 20 end
  elseif st == "dodge" or st == "jump" then        -- through him, or onto him
    if st == "dodge" then s.vx = s.face * 3.2 end
    if not s.landed and shadows.overlap(s.x, s.y, s.w, s.h, k) and body.hurt(ink(MR.touch), s.x + s.w / 2) then
      s.landed = true
      shadows.hits = shadows.hits + 1
    end
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "rest", 20 end
  else
    s.vx, s.t = s.vx * 0.8, s.t - 1
    if s.t <= 0 then s.state = "walk" end
  end
end

function mirror.strike(s, n, dir, heavy)
  if s.state == "walk" or heavy then s.state, s.t = "reel", 14 end
  s.vx = dir * 1.5
  return "hit"
end

-- Komali's own frames (body.lua), in ink, eyes lit
function mirror.draw(s)
  local st, f = s.state, 0
  if st == "strike" then f = 14 elseif st == "dodge" then f = 10 + stat("frame") // 4 % 2
  elseif st == "jump" then f = s.vy < 0 and 8 or 9 elseif st == "reel" then f = 13
  elseif math.abs(s.vx) > 0.2 then f = 2 + s.step // 8 % 6 end
  for c = 1, 31 do pal(c, c % 4 == 0 and C.blue or c % 3 == 0 and C.navy or C.ink) end
  pal(C.cloth, C.sky) pal(C.glow, C.glow)
  spr(f * 3, math.floor(s.x) - 7, math.floor(s.y) - 12, 3, 4, s.face < 0)
  pal()
end

-- ---- the cinder ----
local cinder = { mai = CN.mai, fly = true }

function cinder.add(s)
  s.x, s.y, s.w, s.h = s.x, s.y + 12, 8, 8
  s.hp = CN.hp
end

local function burst(s, body, k)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  for a = 0, 7 do fx.spark(cx + math.cos(a * 0.785) * 14, cy + math.sin(a * 0.785) * 14) end
  if math.abs(k.x + k.w / 2 - cx) < CN.r and math.abs(k.y + k.h / 2 - cy) < CN.r and body.hurt(ink(CN.n), cx) then
    shadows.hits = shadows.hits + 1
  end
  s.state = "boom"
  for _, o in ipairs(shadows.list) do             -- it burns its own side too
    if o.on and o ~= s and not o.prop and math.abs(o.x + o.w / 2 - cx) < CN.r and math.abs(o.y + o.h / 2 - cy) < CN.r then
      shadows.strike(o, CN.hurts, o.x > cx and 1 or -1, true)
    end
  end
  shadows.strike(s, 99, 1, true)                   -- and is gone
end

function cinder.update(s, body, k, dx)
  local dy = k.y + k.h / 2 - (s.y + s.h / 2)
  if s.state == "walk" then
    local len = math.max(1, math.sqrt(dx * dx + dy * dy))
    s.vx, s.vy = dx / len * CN.speed, dy / len * CN.speed + math.sin(s.step * 0.1) * 0.2
    if len < CN.near then s.state, s.t, s.vx, s.vy = "wind", CN.fuse, 0, 0 end
  elseif s.state == "wind" then
    s.vx, s.vy = 0, 0
    s.t = s.t - 1
    if s.t <= 0 then burst(s, body, k) return end
  end
  s.step = s.step + 1
  s.x, s.y = s.x + s.vx, s.y + s.vy
end

-- struck, it burns down fast
function cinder.strike(s, n, dir)
  if s.state == "boom" then return "hit" end
  if s.state ~= "wind" or s.t > CN.struck then s.state, s.t = "wind", CN.struck end
  s.vx = 0
  return nil
end

function cinder.draw(s)
  local f, cx, cy = stat("frame"), s.x + s.w / 2, s.y + s.h / 2
  local r = 3 + (f // 4) % 2
  if s.state == "wind" then
    r = 3 + (CN.fuse - s.t) // 8
    if s.t % 4 < 2 then circfill(cx, cy, r + 1, C.glow) end
  end
  circfill(cx, cy, r, C.red)
  circfill(cx, cy - 1, r - 1, C.vermil)
  circfill(cx, cy - 1, math.max(1, r - 2), C.lamp)
  pset(cx + (f % 3) - 1, cy - r - 1 - f % 2, C.saffron)
end

shadows.kinds.lampguard, shadows.kinds.mirror, shadows.kinds.cinder = guard, mirror, cinder

return palace
