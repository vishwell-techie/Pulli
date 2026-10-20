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

local shadows = require("shadows")
local fx      = require("fx")

local boss = {}

local B = {
  hp = 160,
  speed = 0.7,
  wind = { combo = 20, heavy = 45, bash = 16 },   -- frames of warning (twice the first time)
  slash = { n = 10, reach = 20, gap = 16 },        -- each of the three slashes
  heavy = { n = 22, reach = 30, frames = 6 },
  bash = { n = 12, speed = 2.2, frames = 30 },
  rest = { combo = 50, heavy = 70, bash = 40 },
  mai = { 40, 50 },
  oil = 8,
  role = "veeran",                               -- the role he lends, beaten
}
boss.B = B

-- Sprites (16x24): on guard, walking, winding up, striking, gathering, the
-- dash, struck.
local GUARD, WALK, WIND, STRIKE, GATHER, BASH, REEL = 704, 706, 708, 710, 712, 714, 716

local function overlap(ax, ay, aw, ah, b)
  return ax < b.x + b.w and b.x < ax + aw and ay < b.y + b.h and b.y < ay + ah
end

local kind = { mai = B.mai }

function kind.add(s)
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
    s.vx = dist > 26 and s.face * B.speed or 0
    s.think = s.think - 1
    if s.think <= 0 then
      local m
      if dist < 34 then m = "combo"
      elseif dist > 80 then m = "bash"
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
      if overlap(bx, s.y + 2, B.slash.reach, 14, k) and hurt(s, body, B.slash.n) then s.landed = true end
    end
    s.vx = s.vx * 0.8
    if s.count >= 3 and f == B.slash.gap - 1 then s.state, s.t = "rest", math.floor(B.rest.combo * tired) end
  elseif st == "heavy" then
    s.t = s.t + 1
    if not s.landed then
      local bx = s.face > 0 and s.x + s.w or s.x - B.heavy.reach
      if overlap(bx, s.y, B.heavy.reach, 20, k) and hurt(s, body, B.heavy.n) then s.landed = true end
    end
    if s.t >= B.heavy.frames then s.state, s.t = "rest", math.floor(B.rest.heavy * tired) end
  elseif st == "bash" then
    s.t = s.t + 1
    s.vx = s.face * B.bash.speed
    if not s.landed and overlap(s.x - 2, s.y, s.w + 4, s.h, k) and hurt(s, body, B.bash.n) then s.landed = true end
    if s.t >= B.bash.frames then s.state, s.t, s.vx = "rest", math.floor(B.rest.bash * tired), 0 end
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
  local x, y, st = math.floor(s.x) - 3, math.floor(s.y) - 4, s.state
  local n = GUARD
  if st == "walk" then n = math.abs(s.vx) > 0.1 and (s.step // 8 % 2 == 0 and WALK or GUARD) or GUARD
  elseif st == "wind" then n = s.move == "heavy" and GATHER or WIND
  elseif st == "combo" or st == "heavy" then n = STRIKE
  elseif st == "bash" then n = BASH
  elseif st == "reel" then n = REEL end
  if st == "wind" and s.t < 8 and s.t % 2 == 0 then pal(12, 7) pal(28, 7) pal(6, 7) end   -- about to strike
  spr(n, x, y, 2, 3, s.face < 0)
  pal()
  local hx, hy = x + 8 + s.face * 5, y + 13
  if st == "wind" then
    line(hx, hy, hx - s.face * 7, hy - 12, 6)
    if s.move == "heavy" and stat("frame") % 4 < 2 then circ(hx - s.face * 7, hy - 12, 3, 10) end
  elseif st == "combo" and s.t % B.slash.gap <= 4 then line(hx, hy, hx + s.face * 18, hy - 2, 7)
  elseif st == "heavy" then line(hx, hy - 4, hx + s.face * 26, hy + 2, 10)
  elseif st == "bash" then circfill(hx + s.face * 3, hy - 2, 6, 4) circ(hx + s.face * 3, hy - 2, 6, 9)
  else line(hx, hy, hx + s.face * 3, hy + 10, 6) end
end

shadows.kinds.veeran = kind

return boss
