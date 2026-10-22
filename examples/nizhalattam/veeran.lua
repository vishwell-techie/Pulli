-- veeran.lua — Veeran, the warrior, the Screen's boss: a captured puppet
-- wearing the role the Puppet King forced on him.
--
--   require("veeran")        adds the kind "veeran" to shadows.lua; rooms.lua
--                            does this in the boss's room only, and lets the
--                            code go when Komali leaves it
--   shadows.boss             the boss in the room; shadows.beaten is set
--                            when he is torn, and main.lua lends his role
--
-- He walks up with his guard to the front (light blows from the front are
-- turned aside), then does one of three moves, each with a wind-up that
-- warns of it: three slashes up close; a heavy slash, gathered long and
-- shining, from a little way off; and a dash behind his shield from afar,
-- which no blow from the front stops. The first time he does a move, its
-- wind-up is twice as long: he shows it before he means it. After each he
-- rests, open to blows. Below half his health he rests less.
--
-- His shadow (s.shade: once he is saved, or in hard mode) slashes five
-- times, not three; from a middle distance, and every other time from
-- afar in place of his dash, he leaps at Komali, crouching first (the
-- warning), and slashes where he lands.

local shadows = require("shadows")
local C       = require("colours")
local fx      = require("fx")
local move    = require("move")

local boss = { kinds = { "veeran" } }

local B = {
  hp = 160,
  w = 20, h = 40,                                  -- twice Komali's size: no single jump clears him
  speed = 0.7,
  wind = { combo = 20, heavy = 45, bash = 16, leap = 24 },   -- frames of warning (twice the first time)
  slash = { n = 10, reach = 30, gap = 16 },        -- each of the three slashes
  heavy = { n = 22, reach = 44, frames = 6 },
  bash = { n = 12, speed = 2.2, frames = 30 },
  leap = { n = 16, up = 5, frames = 40, reach = 30 },     -- (the shadow's)
  rest = { combo = 50, heavy = 70, bash = 40, leap = 50 },
  mai = { 40, 50 },
  oil = 8,
  role = "veeran",                               -- the role he lends, beaten
}
boss.B = B

-- Sprites in actors.png (48x64, twice the size, see art.py): on guard,
-- walking (four), winding up, striking, gathering, the dash, struck. His
-- sword and shield are on them.
local GUARD, WALK, WIND, STRIKE, GATHER, BASH, REEL = 1024, 1030, 1054, 1060, 1066, 1072, 1078

local function overlap(ax, ay, aw, ah, b)
  return ax < b.x + b.w and b.x < ax + aw and ay < b.y + b.h and b.y < ay + ah
end

local kind = { mai = B.mai }

function kind.add(s)
  s.x, s.y, s.w, s.h = s.x + 5 - B.w / 2, s.y + 20 - B.h, B.w, B.h
  s.hp, s.max, s.shown, s.think, s.turn = B.hp, B.hp, {}, 40, 0
  s.oil, s.role = B.oil, B.role
  shadows.boss, shadows.beaten = s, false
end

local function hurt(s, body, n)
  if body.hurt(math.max(1, math.floor(n * shadows.soft + 0.5)), s.x + s.w / 2) then shadows.hits = shadows.hits + 1 return true end
end

function kind.update(s, body, k, dx)
  local st = s.state
  local tired = s.hp < s.max / 2 and 0.7 or 1
  if st == "walk" then
    s.face = dx < 0 and -1 or 1
    local dist = math.abs(dx)
    s.vx = dist > 34 and s.face * B.speed or 0
    s.think = s.think - 1
    if s.think <= 0 then
      local m
      if dist < 44 then m = "combo"
      elseif dist > 110 or (s.shade and dist > 64) then
        -- the shadow leaps from a middle distance, and every other time from afar
        s.far = (s.far or 0) + 1
        m = s.shade and (dist <= 110 or s.far % 2 == 0) and "leap" or "bash"
      else s.turn = s.turn + 1; m = s.turn % 2 == 1 and "heavy" or "combo" end
      s.move, s.state, s.vx = m, "wind", 0
      s.t = B.wind[m] * (s.shown[m] and 1 or 2)
      s.shown[m] = true
    end
  elseif st == "wind" then
    s.vx = 0
    s.t = s.t - 1
    if s.t <= 0 then
      s.state, s.t, s.landed, s.count = s.move, 0, false, 0
    end
  elseif st == "combo" then
    s.t = s.t + 1
    local f = s.t % B.slash.gap
    if f == 1 then s.landed, s.count = false, s.count + 1; s.vx = s.face * 1.2 end
    if f >= 1 and f <= 4 and not s.landed then
      local bx = s.face > 0 and s.x + s.w or s.x - B.slash.reach
      if overlap(bx, s.y + 8, B.slash.reach, 26, k) and hurt(s, body, B.slash.n) then s.landed = true end
    end
    s.vx = s.vx * 0.8
    if s.count >= (s.shade and 5 or 3) and f == B.slash.gap - 1 then s.state, s.t = "rest", math.floor(B.rest.combo * tired) end
  elseif st == "heavy" then
    s.t = s.t + 1
    if not s.landed then
      local bx = s.face > 0 and s.x + s.w or s.x - B.heavy.reach
      if overlap(bx, s.y, B.heavy.reach, B.h, k) and hurt(s, body, B.heavy.n) then s.landed = true end
    end
    if s.t >= B.heavy.frames then s.state, s.t = "rest", math.floor(B.rest.heavy * tired) end
  elseif st == "bash" then
    s.t = s.t + 1
    s.vx = s.face * B.bash.speed
    if not s.landed and overlap(s.x - 2, s.y, s.w + 4, s.h, k) and hurt(s, body, B.bash.n) then s.landed = true end
    if s.t >= B.bash.frames then s.state, s.t, s.vx = "rest", math.floor(B.rest.bash * tired), 0 end
  elseif st == "leap" then
    -- up and over to where Komali stood, the blade coming down as he lands
    if s.t == 0 then
      local to = k.x + k.w / 2 - (s.x + s.w / 2)
      s.vx, s.vy = math.max(-4, math.min(4, to / 34)), -B.leap.up
    end
    s.t = s.t + 1
    if s.t > 4 and s.vy >= 0 and move.blocked(s.x, s.y + s.h, s.w, 1) then
      s.vx = 0
      if not s.landed then
        s.landed = true
        fx.spark(s.x + s.w / 2 - 14, s.y + s.h - 2) fx.spark(s.x + s.w / 2 + 14, s.y + s.h - 2)
        if overlap(s.x - B.leap.reach, s.y + 8, s.w + B.leap.reach * 2, s.h - 8, k) then hurt(s, body, B.leap.n) end
      end
      s.state, s.t = "rest", math.floor(B.rest.leap * tired)
    elseif s.t > B.leap.frames * 2 then s.state, s.t = "rest", B.rest.leap end
  elseif st == "rest" or st == "reel" then
    s.vx = s.vx * 0.85
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.think = "walk", 30 end
  end
end

-- His guard: light blows from the front are turned aside while he walks,
-- and nothing from the front stops his dash. A heavy blow while he walks
-- staggers him.
function kind.strike(s, n, dir, heavy)
  local front = dir == -s.face
  if front and (s.state == "bash" or (s.state == "walk" and not heavy)) then
    fx.spark(s.x + s.w / 2 + s.face * 6, s.y + 10)
    return "blocked"
  end
  if heavy and s.state == "walk" then s.state, s.t = "reel", 16 end
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
  if st == "walk" then n = math.abs(s.vx) > 0.1 and WALK + s.step // 6 % 4 * 3 or GUARD
  elseif st == "wind" then n = s.move == "heavy" and GATHER or WIND
  elseif st == "leap" then n = s.vy < 0 and GATHER or STRIKE
  elseif st == "combo" or st == "heavy" then n = STRIKE
  elseif st == "bash" then n = BASH
  elseif st == "reel" then n = REEL end
  if st == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.blue, C.glow) pal(C.sky, C.glow) pal(C.marigold, C.glow) end
  spr(n, x, y, 6, 8, s.face < 0)
  pal()
  local cx = x + 24
  if st == "wind" and s.move == "heavy" and stat("frame") % 4 < 2 then circ(cx - s.face * 8, y + 4, 4, C.glow) end
  -- the sweep of a blow that can land
  if (st == "combo" and s.t % B.slash.gap <= 4) or st == "heavy" then
    local r = st == "heavy" and 46 or 34
    for n = 0, 3 do
      local a0 = -1.0 + n * 0.5
      line(cx + s.face * math.cos(a0) * r, y + 38 + math.sin(a0) * 20,
           cx + s.face * math.cos(a0 + 0.5) * r, y + 38 + math.sin(a0 + 0.5) * 20, st == "heavy" and C.lamp or C.glow)
    end
  end
end

shadows.kinds.veeran = kind

return boss
