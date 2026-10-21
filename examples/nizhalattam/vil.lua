-- vil.lua — Vil, the archer, the Painted Forest's boss: a captured puppet
-- wearing the role the Puppet King forced on him.
--
--   require("vil")           adds the kind "vil" to shadows.lua; rooms.lua
--                            does this in his glade only
--   shadows.boss             the boss in the room; shadows.beaten is set
--                            when he is torn, and main.lua lends his role
--
-- He keeps his distance. From afar he draws and looses an arrow aimed at
-- Komali, or a volley of three, one after another; as he draws, a line of
-- light shows where he aims, and the bow flashes before it looses. Come too
-- close and he leaps away (over Komali, if a wall is behind him). The first
-- time he does a move its warning is twice as long. After each he rests,
-- open to blows; a heavy blow while he draws breaks his aim. Below half his
-- health he rests less. Twice Komali's size, like Veeran: no single jump
-- clears him.

local shadows = require("shadows")
local shots   = require("shots")
local move    = require("move")
local fx      = require("fx")
local C       = require("colours")

local boss = { kinds = { "vil" } }

local B = {
  hp = 150,
  w = 20, h = 40,
  speed = 0.6,
  near = 56,                                       -- closer than this, he leaps away
  far = 150,                                       -- further than this, he walks closer
  wind = { shot = 24, volley = 30, leap = 10 },    -- frames of warning (twice the first time)
  arrow = { n = 10, speed = 3.2, life = 110 },
  volley = { count = 3, gap = 14 },
  leap = { up = 4.4, across = 2.4 },
  rest = { shot = 40, volley = 60, leap = 12 },
  mai = { 40, 50 },
  oil = 9,
  role = "vil",                                    -- the role he lends, beaten
}
boss.B = B

-- Sprites in vil.kolam (48x64, see art.py): on guard, walking (four),
-- drawing, loosing, leaping, crouching, struck.
local SHEET = "vil.kolam"
local GUARD, WALK, DRAW, LOOSE, LEAP, CROUCH, REEL = 0, 6, 30, 36, 42, 48, 54

local kind = { mai = B.mai }

function kind.add(s)
  s.x, s.y, s.w, s.h = s.x + 5 - B.w / 2, s.y + 20 - B.h, B.w, B.h
  s.hp, s.max, s.shown, s.think, s.turn = B.hp, B.hp, {}, 40, 0
  s.oil, s.role, s.ax, s.ay, s.loosed = B.oil, B.role, 0, 0, 99
  shadows.boss, shadows.beaten = s, false
end

-- where his arrows leave the bow: ahead of him, at the shoulder
local function bow(s) return s.x + s.w / 2 + s.face * 14, s.y + 8 end

local function aim(s, k)
  local bx, by = bow(s)
  local ex, ey = k.x + k.w / 2 - bx, k.y + k.h / 2 - by
  local len = math.max(1, math.sqrt(ex * ex + ey * ey))
  s.ax, s.ay = ex / len, ey / len
end

local function loose(s, k)
  aim(s, k)
  local bx, by = bow(s)
  local v = B.arrow.speed
  shots.fire(bx, by, s.ax * v, s.ay * v, B.arrow.life, B.arrow.n, false)
  s.loosed = 0
end

function kind.update(s, body, k, dx)
  local st = s.state
  local tired = s.hp < s.max / 2 and 0.7 or 1
  s.loosed = s.loosed + 1
  if st == "walk" then
    s.face = dx < 0 and -1 or 1
    local dist = math.abs(dx)
    s.vx = dist > B.far and s.face * B.speed or 0
    s.think = s.think - 1
    if dist < B.near or s.think <= 0 then
      local m = "leap"
      if dist >= B.near then s.turn = s.turn + 1; m = s.turn % 2 == 1 and "shot" or "volley" end
      s.move, s.state, s.vx = m, "wind", 0
      s.t = B.wind[m] * (s.shown[m] and 1 or 2)
      s.shown[m] = true
    end
  elseif st == "wind" then
    s.vx = 0
    if s.move ~= "leap" then s.face = dx < 0 and -1 or 1 aim(s, k) end
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t, s.count = s.move, 0, 0 end
  elseif st == "shot" then
    loose(s, k)
    s.state, s.t = "rest", math.floor(B.rest.shot * tired)
  elseif st == "volley" then
    s.t = s.t + 1
    if s.t % B.volley.gap == 1 then loose(s, k) s.count = s.count + 1 end
    if s.count >= B.volley.count and s.t % B.volley.gap == B.volley.gap - 1 then
      s.state, s.t = "rest", math.floor(B.rest.volley * tired)
    end
  elseif st == "leap" then
    if s.t == 0 then
      -- away from Komali, or over him if a wall is close behind
      local away = -s.face
      local behind = away > 0 and s.x + s.w + 40 or s.x - 41
      if move.blocked(behind, s.y, 1, s.h - 2) then away = s.face end
      s.vx, s.vy = away * B.leap.across * (away == s.face and 1.3 or 1), -B.leap.up
    end
    s.t = s.t + 1
    if s.t > 4 and s.vy >= 0 and move.blocked(s.x, s.y + s.h, s.w, 1) then
      s.state, s.t, s.vx = "rest", B.rest.leap, 0
    end
  elseif st == "rest" or st == "reel" then
    s.vx = s.vx * 0.85
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.think = "walk", st == "rest" and s.move == "leap" and 8 or 30 end
  end
end

-- No guard; a heavy blow while he walks or draws breaks it off.
function kind.strike(s, n, dir, heavy)
  if heavy and (s.state == "walk" or s.state == "wind") then s.state, s.t, s.vx = "reel", 16, dir * 1.5 end
  return "hit"
end

function kind.torn(s)
  shadows.beaten = true
  fx.tear(s.x + s.w / 2, s.y + 4, 0)
  fx.tear(s.x + s.w / 2, s.y + 16, 0)
end

function kind.draw(s)
  local x, y, st = math.floor(s.x + s.w / 2) - 24, math.floor(s.y + s.h) - 63, s.state
  local n = GUARD
  if st == "walk" then n = math.abs(s.vx) > 0.1 and WALK + s.step // 6 % 4 * 6 or GUARD
  elseif st == "wind" then n = s.move == "leap" and CROUCH or DRAW
  elseif st == "shot" or st == "volley" then n = s.loosed < 8 and LOOSE or DRAW
  elseif st == "leap" then n = LEAP
  elseif st == "reel" then n = REEL
  elseif s.loosed < 8 then n = LOOSE end
  -- drawing, a line of light shows where the arrow will go
  if st == "wind" and s.move ~= "leap" then
    local bx, by = bow(s)
    for d = 1, 7 do
      if (d + stat("frame") // 3) % 2 == 0 then pset(bx + s.ax * d * 12, by + s.ay * d * 12, C.lamp) end
    end
  end
  if st == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.leaf, C.glow) pal(C.marigold, C.glow) end
  sheet.load(SHEET)
  spr(n, x, y, 6, 8, s.face < 0)
  sheet.load("actors.kolam")
  pal()
end

shadows.kinds.vil = kind

return boss
