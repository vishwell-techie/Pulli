-- yaanai.lua — the Elephant (Yaanai), the Battlefield of Flags' boss: a
-- captured puppet wearing the role the Puppet King forced on him.
--
--   require("yaanai")        adds the kind "yaanai" to shadows.lua; rooms.lua
--                            does this in his field only
--   shadows.boss             the boss in the room; shadows.beaten is set
--                            when he is torn, and main.lua lends his role
--
-- He is slow and cannot be stopped: no blow breaks off what he does. He
-- paws the ground (the warning) and charges wall to wall; the wall stops
-- him, dizzy, open to blows. Or he rears (the warning) and pounds the
-- ground: a shockwave runs along it either way, which only reaches feet on
-- the ground. The first time he does a move its warning is twice as long.
-- Below half his health he rests less. Bigger than Komali: only a double
-- jump clears him.
--
-- His shadow (s.shade: once he is saved, or in hard mode) turns at the wall
-- and charges again before he stands dizzy; and his pound shakes stones
-- loose from above, which fall one after another about Komali (a mark on
-- the ground shows where).

local shadows = require("shadows")
local move    = require("move")
local fx      = require("fx")
local C       = require("colours")
local sound   = require("sound")

local boss = { kinds = { "yaanai" } }

local B = {
  hp = 220,
  w = 44, h = 44,
  speed = 0.5,
  wind = { charge = 34, pound = 30 },              -- frames of warning (twice the first time)
  charge = { speed = 4.2, n = 16 },
  pound = { n = 12, speed = 3.2, life = 80, high = 8 },
  rest = { charge = 80, pound = 50 },               -- after a charge he stands dizzy
  turn = 16,                                        -- (the shadow's) frames turning at the wall
  stones = { count = 3, gap = 14, spread = 28, fall = 0.25, n = 10 },
  mai = { 45, 55 },
  oil = 12,
  role = "yaanai",                                 -- the role he lends, beaten
}
boss.B = B

-- Sprites in yaanai.kolam (64x64, see art.py): standing, walking (four),
-- pawing, charging, rearing; pounding, dizzy, trumpeting (second row).
local SHEET = "yaanai.kolam"
local STAND, WALK, PAW, CHARGE, REAR, POUND, DIZZY, TRUMPET = 0, 8, 40, 48, 56, 512, 520, 528

-- the shadow's stones: a few long arrays (where, falling how fast, frames
-- until they let go)
local NS = 3
local sx, sy, sv, sd = {}, {}, {}, {}
for n = 1, NS do sx[n], sy[n], sv[n], sd[n] = 0, 0, 0, -1 end

local kind = { mai = B.mai }

function kind.add(s)
  s.x, s.y, s.w, s.h = s.x + 5 - B.w / 2, s.y + 20 - B.h, B.w, B.h
  s.hp, s.max, s.shown, s.think, s.turn, s.wt = B.hp, B.hp, {}, 60, 0, 0
  s.oil, s.role, s.again = B.oil, B.role, false
  shadows.boss, shadows.beaten = s, false
  for n = 1, NS do sd[n] = -1 end
end

function kind.update(s, body, k, dx)
  local st = s.state
  local tired = s.hp < s.max / 2 and 0.7 or 1
  if st == "walk" then
    s.face = dx < 0 and -1 or 1
    s.vx = math.abs(dx) > 90 and s.face * B.speed or 0
    s.think = s.think - 1
    if s.think <= 0 then
      s.turn = s.turn + 1
      local m = s.turn % 2 == 1 and "charge" or "pound"
      s.move, s.state, s.vx = m, "wind", 0
      s.t = B.wind[m] * (s.shown[m] and 1 or 2)
      s.shown[m] = true
    end
  elseif st == "wind" then
    s.vx = 0
    if not s.again then s.face = dx < 0 and -1 or 1 end
    s.t = s.t - 1
    if s.t <= 0 then
      s.state, s.t, s.landed = s.move, 0, false
      if s.move == "pound" and s.shade then          -- the shadow's stones, about Komali
        local S = B.stones
        for n = 1, NS do
          sx[n], sy[n], sv[n], sd[n] = k.x + k.w / 2 + (n - 2) * S.spread, 0, 0, 10 + (n - 1) * S.gap
        end
      end
      if s.move == "pound" then sound.play("pound") end
      if s.move == "pound" then                     -- the shockwave, either way from his feet
        s.wl, s.wr, s.wt, s.hitl, s.hitr = s.x + s.w / 2, s.x + s.w / 2, B.pound.life, false, false
        fx.spark(s.x + s.w / 2 + s.face * 20, s.y + s.h - 2)
      end
    end
  elseif st == "charge" then
    local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
    if move.blocked(ahead, s.y, 1, s.h - 2) and s.shade and not s.again then
      -- the shadow turns at the wall and comes again
      s.again, s.face, s.vx = true, -s.face, 0
      s.state, s.t, s.landed = "wind", B.turn, false
    elseif move.blocked(ahead, s.y, 1, s.h - 2) then    -- the wall: he stands dizzy
      s.state, s.t, s.vx, s.again = "rest", math.floor(B.rest.charge * tired), 0, false
    else
      s.vx = s.face * B.charge.speed
      if not s.landed and shadows.overlap(s.x, s.y, s.w, s.h, k) and body.hurt(B.charge.n, s.x + s.w / 2) then
        s.landed = true
        shadows.hits = shadows.hits + 1
      end
    end
  elseif st == "pound" then
    s.t = s.t + 1
    if s.t > 12 then s.state, s.t = "rest", math.floor(B.rest.pound * tired) end
  elseif st == "rest" then
    s.vx = s.vx * 0.85
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.think = "walk", math.floor(50 * tired) end
  end
  for n = 1, NS do                                  -- the stones: waiting, then falling
    if sd[n] > 0 then sd[n] = sd[n] - 1
    elseif sd[n] == 0 then
      sv[n] = sv[n] + B.stones.fall
      sy[n] = sy[n] + sv[n]
      if move.blocked(sx[n], sy[n] + 4, 1, 1) then
        sd[n] = -1
        fx.spark(sx[n], sy[n])
      elseif sx[n] + 4 > k.x and sx[n] - 4 < k.x + k.w and sy[n] + 4 > k.y and sy[n] - 4 < k.y + k.h then
        sd[n] = -1
        if body.hurt(B.stones.n, sx[n]) then shadows.hits = shadows.hits + 1 end
      end
    end
  end
  if s.wt > 0 then                                  -- the shockwave rolls on along the ground
    s.wt = s.wt - 1
    local P, floor = B.pound, s.y + s.h
    s.wl, s.wr = s.wl - P.speed, s.wr + P.speed
    if move.blocked(s.wl, floor - 4, 1, 2) then s.hitl = true end
    if move.blocked(s.wr, floor - 4, 1, 2) then s.hitr = true end
    local feet = k.y + k.h
    if feet > floor - P.high and feet <= floor + 1 then
      for side = 1, 2 do
        local x, gone = side == 1 and s.wl or s.wr, side == 1 and s.hitl or s.hitr
        if not gone and x > k.x - 2 and x < k.x + k.w + 2 and body.hurt(P.n, x) then
          shadows.hits = shadows.hits + 1
        end
      end
    end
  end
end

-- Nothing stops him: a blow lands, and he carries on.
function kind.strike(s, n, dir, heavy) return "hit" end

function kind.torn(s)
  shadows.beaten = true
  for n = 1, NS do sd[n] = -1 end
  fx.tear(s.x + s.w / 2, s.y + 8, 0)
  fx.tear(s.x + s.w / 2, s.y + 24, 0)
end

function kind.draw(s)
  local x, y, st, f = math.floor(s.x + s.w / 2) - 30, math.floor(s.y + s.h) - 63, s.state, stat("frame")
  local n = STAND
  if st == "walk" then n = math.abs(s.vx) > 0.1 and WALK + s.step // 8 % 4 * 8 or STAND
  elseif st == "wind" then n = s.move == "charge" and PAW or REAR
  elseif st == "charge" then n = CHARGE
  elseif st == "pound" then n = POUND
  elseif st == "rest" then n = s.move == "charge" and DIZZY or STAND end
  if st == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.red, C.glow) pal(C.marigold, C.glow) end
  sheet.load(SHEET)
  spr(n, x, y, 8, 8, s.face < 0)
  sheet.load("actors.kolam")
  pal()
  -- dizzy after the wall: stars about his head; the charge throws up dust
  if st == "rest" and s.move == "charge" then
    for d = 0, 2 do
      local a = f * 0.12 + d * 2.1
      pset(s.x + s.w / 2 + s.face * 14 + math.cos(a) * 9, s.y - 2 + math.sin(a) * 3, C.lamp)
    end
  elseif st == "charge" and f % 3 == 0 then
    fx.spark(s.x + s.w / 2 - s.face * 22, s.y + s.h - 2)
  end
  for n = 1, NS do                                  -- the stones, and the marks where they will fall
    if sd[n] >= 0 then
      local floor = s.y + s.h
      if f % 4 < 2 then line(sx[n] - 4, floor - 1, sx[n] + 4, floor - 1, C.vermil) end
      if sd[n] == 0 then
        circfill(sx[n], sy[n], 4, C.leather)
        pset(sx[n] - 1, sy[n] - 2, C.tan)
      end
    end
  end
  if s.wt > 0 then
    local floor, h = s.y + s.h, 2 + s.wt // 20
    for side = 1, 2 do
      local wx, gone = side == 1 and s.wl or s.wr, side == 1 and s.hitl or s.hitr
      if not gone then
        line(wx, floor - 1, wx, floor - h * 2, C.marigold)
        line(wx - 2, floor - 1, wx - 2, floor - h, C.tan)
        line(wx + 2, floor - 1, wx + 2, floor - h, C.tan)
      end
    end
  end
end

shadows.kinds.yaanai = kind

return boss
