-- flags.lua — the Battlefield of Flags' own shadows, added to shadows.lua's
-- kinds. rooms.lua requires it in the battlefield's rooms only, and lets
-- the code go when Komali leaves the story.
--
-- Archers stand in a line and loose together: all of them draw at once (a
-- line of light shows where each aims), then all loose at Komali. Struck
-- while drawing, one misses that volley. Their arrows are shots.lua's, so
-- their rooms want arrows.
-- The flag-bearer keeps behind the others and rallies them: a shadow near
-- its flag takes half of every blow (s.rally, shadows.lua). Come close and
-- it swings the pole.
-- The war drum stands and beats: the drummer raises the sticks (the
-- warning), and the beat sends a shockwave along the ground either way. It
-- only reaches feet on the ground: jump it.

local shadows = require("shadows")
local fight   = require("fight")
local move    = require("move")
local C       = require("colours")

local flags = { kinds = { "archer", "flag", "drum" } }

local AR = { hp = 14, sight = 240, every = 150, draw = 30, speed = 2.6, life = 120, n = 8, mai = { 2, 4 } }
local FL = { hp = 16, rally = 72, near = 70, far = 130, speed = 0.5, reach = 26, wind = 16, swing = 6, n = 8,
             rest = 30, mai = { 3, 5 } }
local DR = { hp = 30, every = 120, wind = 24, speed = 2.5, life = 90, n = 10, high = 8, mai = { 3, 6 } }
flags.AR, flags.FL, flags.DR = AR, FL, DR

-- Sprites in actors.png (see art.py): the archer standing, drawing,
-- loosing (24x32); the flag-bearer holding its flag up, swinging (24x32);
-- the war drum, sticks raised and beating (32x24).
local ARCHER, BEARER, DRUM = 1844, { 60, 316 }, 624

local function ink(n) return math.max(1, math.floor(n * shadows.soft + 0.5)) end

-- ---- the archer ----
local archer = { mai = AR.mai }

function archer.add(s)
  s.hp = AR.hp
end

-- where its arrow leaves the bow, and where it aims
local function bow(s) return s.x + s.w / 2 + s.face * 8, s.y + 4 end

function archer.update(s, body, k, dx)
  local phase = stat("frame") % AR.every                -- every archer keeps the same time
  s.vx = 0
  if s.state == "reel" then
    s.t = s.t - 1
    if s.t <= 0 then s.state = "walk" end
    return
  end
  local seen = math.abs(dx) < AR.sight and math.abs(k.y - s.y) < 80
  if seen then s.face = dx < 0 and -1 or 1 end
  if phase == AR.every - AR.draw and seen then s.state = "wind" end
  if s.state == "wind" then
    local bx, by = bow(s)
    local ex, ey = k.x + k.w / 2 - bx, k.y + k.h / 2 - by
    local len = math.max(1, math.sqrt(ex * ex + ey * ey))
    s.ax, s.ay = ex / len, ey / len
    if phase == AR.every - 1 then
      if fight.shots then fight.shots.fire(bx, by, s.ax * AR.speed, s.ay * AR.speed, AR.life, ink(AR.n), false) end
      s.state, s.t = "rest", 12
    end
  elseif s.state == "rest" then
    s.t = s.t - 1
    if s.t <= 0 then s.state = "walk" end
  end
end

function archer.strike(s, n, dir, heavy)
  if s.state == "wind" then s.state, s.t = "reel", 14 end      -- its aim broken: it misses the volley
  return "hit"
end

function archer.draw(s)
  local st = s.state
  if st == "wind" then
    local bx, by = bow(s)
    for d = 1, 6 do
      if (d + stat("frame") // 3) % 2 == 0 then pset(bx + s.ax * d * 10, by + s.ay * d * 10, C.vermil) end
    end
    if stat("frame") % AR.every > AR.every - 8 and stat("frame") % 2 == 0 then pal(C.cloth, C.glow) end
  end
  spr(ARCHER + (st == "wind" and 3 or st == "rest" and 6 or 0), math.floor(s.x) - 7, math.floor(s.y) - 12, 3, 4,
      s.face < 0)
  pal()
end

-- ---- the flag-bearer ----
local flag = { mai = FL.mai }

function flag.add(s)
  s.hp, s.rally = FL.hp, FL.rally
end

function flag.update(s, body, k, dx)
  local st, dist = s.state, math.abs(dx)
  if st == "walk" then
    s.face = dx < 0 and -1 or 1
    local go = 0
    if dist < FL.reach and math.abs(k.y - s.y) < 24 then
      s.state, s.t, s.vx = "wind", FL.wind, 0
      return
    elseif dist < FL.near then go = -s.face                  -- keeps behind the others
    elseif dist > FL.far then go = s.face end
    local ahead = go > 0 and s.x + s.w + 1 or s.x - 2
    s.vx = (go ~= 0 and move.blocked(ahead, s.y + s.h, 1, 1)) and go * FL.speed or 0
  elseif st == "wind" then
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t, s.landed = "strike", FL.swing, false end
  elseif st == "strike" then
    if not s.landed and shadows.overlap(s.face > 0 and s.x + s.w or s.x - 16, s.y, 16, s.h, k)
       and body.hurt(ink(FL.n), s.x + s.w / 2) then
      s.landed = true
      shadows.hits = shadows.hits + 1
    end
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "rest", FL.rest end
  else
    s.vx, s.t = s.vx * 0.8, s.t - 1
    if s.t <= 0 then s.state = "walk" end
  end
end

function flag.draw(s)
  -- the shadows it rallies wear a red pennant over their heads
  for _, o in ipairs(shadows.list) do
    if o.on and o ~= s and not o.rally and math.abs(o.x - s.x) < FL.rally and math.abs(o.y - s.y) < 48 then
      local x, y = math.floor(o.x + o.w / 2), math.floor(o.y) - 14
      line(x, y, x, y + 5, C.wood)
      line(x + 1, y, x + 3, y + 1, C.red)
      pset(x + 1, y + 1, C.red)
    end
  end
  if s.state == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.red, C.glow) end
  spr(BEARER[(s.state == "strike" or s.state == "wind") and 2 or 1], math.floor(s.x) - 7, math.floor(s.y) - 12,
      3, 4, s.face < 0)
  pal()
end

-- ---- the war drum ----
local drum = { mai = DR.mai }

function drum.add(s)
  s.x, s.y, s.w, s.h = s.x - 9, s.y, 28, 20
  s.hp, s.t, s.wt = DR.hp, DR.every // 2, 0
end

function drum.update(s, body, k, dx)
  s.vx = 0
  if s.state == "walk" or s.state == "rest" then
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "wind", DR.wind end
  elseif s.state == "wind" then
    s.t = s.t - 1
    if s.t <= 0 then                                -- the beat: a shockwave either way
      s.state, s.t = "rest", DR.every - DR.wind
      s.wl, s.wr, s.wt, s.hitl, s.hitr = s.x + s.w / 2, s.x + s.w / 2, DR.life, false, false
    end
  else                                              -- reeling: the beat put off
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "rest", DR.every // 2 end
  end
  if s.wt > 0 then
    s.wt = s.wt - 1
    local floor = s.y + s.h
    s.wl, s.wr = s.wl - DR.speed, s.wr + DR.speed
    if move.blocked(s.wl, floor - 4, 1, 2) then s.hitl = true end   -- stopped by a wall
    if move.blocked(s.wr, floor - 4, 1, 2) then s.hitr = true end
    local feet = k.y + k.h
    if feet > floor - DR.high and feet <= floor + 1 then
      for side = 1, 2 do
        local x, gone = side == 1 and s.wl or s.wr, side == 1 and s.hitl or s.hitr
        if not gone and x > k.x - 2 and x < k.x + k.w + 2 and body.hurt(ink(DR.n), x) then
          shadows.hits = shadows.hits + 1
        end
      end
    end
  end
end

function drum.strike(s, n, dir, heavy)
  if heavy and s.state == "wind" then s.state, s.t = "reel", 30 end
  return "hit"
end

function drum.draw(s)
  if s.state == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.red, C.glow) end
  spr(DRUM + ((s.state == "rest" and s.t > DR.every - DR.wind - 10) and 4 or 0), math.floor(s.x) - 2,
      math.floor(s.y) - 4, 4, 3)
  pal()
  if s.wt > 0 then                                  -- the shockwaves: dust rolling along the ground
    local floor, h = s.y + s.h, 2 + s.wt // 20
    for side = 1, 2 do
      local x, gone = side == 1 and s.wl or s.wr, side == 1 and s.hitl or s.hitr
      if not gone then
        line(x, floor - 1, x, floor - h * 2, C.marigold)
        line(x - 2, floor - 1, x - 2, floor - h, C.tan)
        line(x + 2, floor - 1, x + 2, floor - h, C.tan)
      end
    end
  end
end

shadows.kinds.archer, shadows.kinds.flag, shadows.kinds.drum = archer, flag, drum

return flags
