-- rani.lua — the Queen (Rani), the Lamp Palace's boss before the Puppet
-- King: a captured puppet wearing the role he forced on her.
--
--   require("rani")          adds the kind "rani" to shadows.lua; rooms.lua
--                            does this in her hall only
--   shadows.boss             the boss in the room; shadows.beaten is set
--                            when she is torn, and main.lua lends her role
--
-- She raises her lamp (the warning) and sends lamp-fire at Komali, three
-- flames one after another. She lifts the lamp shield: while it holds,
-- blows are turned aside and she mends; three blows break it. Come close
-- and she sends a ring of fire out all round her: roll through it, or be
-- out of its reach. The first time she does a move its warning is twice as
-- long. Below half her health she rests less.
--
-- Her shadow (s.shade: once she is saved, or in hard mode) also casts a
-- ring of fire far out round her that closes in: roll through it as it
-- passes, or be inside her shield's reach when it has gone. It comes in
-- place of every third lamp-fire or shield.

local shadows = require("shadows")
local move    = require("move")
local fx      = require("fx")
local C       = require("colours")
local sound   = require("sound")

local boss = { kinds = { "rani" } }

local B = {
  hp = 180,
  w = 20, h = 40,
  speed = 0.6,
  near = 50, far = 140,
  wind = { fire = 24, shield = 16, ring = 20, close = 30 },   -- frames of warning (twice the first time)
  fire = { count = 3, gap = 12, speed = 3, n = 10, life = 80 },
  shield = { blows = 3, most = 240, mend = 20 },
  ring = { r = 64, frames = 36, n = 12 },
  close = { r = 150, frames = 70 },                -- (the shadow's) the ring closing in
  rest = { fire = 40, shield = 24, ring = 40, close = 40 },
  mai = { 50, 60 },
  oil = 14,
  role = "rani",                                   -- the role she lends, beaten
}
boss.B = B

-- Sprites in rani.kolam (48x64, see art.py): on guard, walking (four),
-- raising the lamp, lamp-fire, the shield, the ring, struck.
local SHEET = "rani.kolam"
local GUARD, WALK, RAISE, FIRE, SHIELD, RING, REEL = 0, 6, 30, 36, 42, 48, 54

-- her flames: a few long arrays
local NF = 4
local fx_, fy, fvx, fvy, fl = {}, {}, {}, {}, {}
for n = 1, NF do fx_[n], fy[n], fvx[n], fvy[n], fl[n] = 0, 0, 0, 0, 0 end

local kind = { mai = B.mai }

function kind.add(s)
  s.x, s.y, s.w, s.h = s.x + 5 - B.w / 2, s.y + 20 - B.h, B.w, B.h
  s.hp, s.max, s.shown, s.think, s.turn, s.ring = B.hp, B.hp, {}, 50, 0, 0
  s.oil, s.role, s.ax, s.ay = B.oil, B.role, 0, 0
  shadows.boss, shadows.beaten = s, false
  for n = 1, NF do fl[n] = 0 end
end

local function lamp(s) return s.x + s.w / 2 + s.face * 12, s.y + 10 end

local function flame(s, k)
  local lx, ly = lamp(s)
  local ex, ey = k.x + k.w / 2 - lx, k.y + k.h / 2 - ly
  local len = math.max(1, math.sqrt(ex * ex + ey * ey))
  for n = 1, NF do
    if fl[n] <= 0 then
      fx_[n], fy[n], fvx[n], fvy[n], fl[n] = lx, ly, ex / len * B.fire.speed, ey / len * B.fire.speed, B.fire.life
      return
    end
  end
end

function kind.update(s, body, k, dx)
  local st = s.state
  local tired = s.hp < s.max / 2 and 0.7 or 1
  local dist = math.abs(dx)
  if st == "walk" then
    s.face = dx < 0 and -1 or 1
    local go = dist > B.far and s.face or 0
    local ahead = go > 0 and s.x + s.w + 1 or s.x - 2
    s.vx = (go ~= 0 and not move.blocked(ahead, s.y, 1, s.h - 2)) and go * B.speed or 0
    s.think = s.think - 1
    if dist < B.near or s.think <= 0 then
      local m = "ring"
      if dist >= B.near then
        s.turn = s.turn + 1
        m = s.turn % 2 == 1 and "fire" or "shield"
        if s.shade and s.turn % 3 == 0 then m = "close" end
      end
      s.move, s.state, s.vx = m, "wind", 0
      s.t = B.wind[m] * (s.shown[m] and 1 or 2)
      s.shown[m] = true
    end
  elseif st == "wind" then
    s.face = dx < 0 and -1 or 1
    s.t = s.t - 1
    if s.t <= 0 then
      s.state, s.t, s.count = s.move, 0, 0
      if s.move == "shield" then s.count = B.shield.blows sound.play("shield") end
      if s.move == "ring" or s.move == "close" then s.landed = false end
    end
  elseif st == "fire" then
    s.t = s.t + 1
    if s.t % B.fire.gap == 1 then flame(s, k) s.count = s.count + 1 end
    if s.count >= B.fire.count and s.t % B.fire.gap == 0 then s.state, s.t = "rest", math.floor(B.rest.fire * tired) end
  elseif st == "shield" then
    s.t = s.t + 1
    if s.t % B.shield.mend == 0 and s.hp < s.max then s.hp = s.hp + 1 end      -- she mends while it holds
    if s.count <= 0 or s.t >= B.shield.most then s.state, s.t = "rest", math.floor(B.rest.shield * tired) end
  elseif st == "ring" then
    s.t = s.t + 1
    s.ring = 8 + (B.ring.r - 8) * s.t / B.ring.frames
    local d = math.sqrt((k.x + k.w / 2 - (s.x + s.w / 2)) ^ 2 + (k.y + k.h / 2 - (s.y + s.h / 2)) ^ 2)
    if not s.landed and math.abs(d - s.ring) < 6 and body.hurt(B.ring.n, s.x + s.w / 2) then
      s.landed = true
      shadows.hits = shadows.hits + 1
    end
    if s.t >= B.ring.frames then s.state, s.t, s.ring = "rest", math.floor(B.rest.ring * tired), 0 end
  elseif st == "close" then
    s.t = s.t + 1
    s.ring = B.close.r - (B.close.r - 8) * s.t / B.close.frames
    local d = math.sqrt((k.x + k.w / 2 - (s.x + s.w / 2)) ^ 2 + (k.y + k.h / 2 - (s.y + s.h / 2)) ^ 2)
    if not s.landed and math.abs(d - s.ring) < 6 and body.hurt(B.ring.n, s.x + s.w / 2) then
      s.landed = true
      shadows.hits = shadows.hits + 1
    end
    if s.t >= B.close.frames then s.state, s.t, s.ring = "rest", math.floor(B.rest.close * tired), 0 end
  elseif st == "rest" or st == "reel" then
    s.vx = s.vx * 0.85
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.think = "walk", math.floor(40 * tired) end
  end
  -- her flames in flight
  for n = 1, NF do
    if fl[n] > 0 then
      fl[n] = fl[n] - 1
      fx_[n], fy[n] = fx_[n] + fvx[n], fy[n] + fvy[n]
      if move.blocked(fx_[n], fy[n], 1, 1) then
        fl[n] = 0
      elseif fx_[n] >= k.x and fx_[n] < k.x + k.w and fy[n] >= k.y and fy[n] < k.y + k.h then
        if body.hurt(B.fire.n, fx_[n] - fvx[n]) then shadows.hits = shadows.hits + 1 end
        fl[n] = 0
      end
    end
  end
end

-- The shield turns every blow aside, until three have broken it; a heavy
-- blow while she walks or gets ready breaks that off.
function kind.strike(s, n, dir, heavy)
  if s.state == "shield" then
    s.count = s.count - 1
    fx.spark(s.x + s.w / 2 - dir * 8, s.y + 10)
    if s.count <= 0 then s.state, s.t = "rest", B.rest.shield end    -- broken
    return "blocked"
  end
  if heavy and (s.state == "walk" or s.state == "wind") then s.state, s.t, s.vx = "reel", 16, dir * 1.5 end
  return "hit"
end

function kind.torn(s)
  shadows.beaten = true
  fx.tear(s.x + s.w / 2, s.y + 4, 0)
  fx.tear(s.x + s.w / 2, s.y + 16, 0)
  for n = 1, NF do fl[n] = 0 end
end

function kind.draw(s)
  local st, f = s.state, stat("frame")
  local n = GUARD
  if st == "walk" then n = math.abs(s.vx) > 0.1 and WALK + s.step // 6 % 4 * 6 or GUARD
  elseif st == "wind" then n = (s.move == "ring" or s.move == "close") and RING or s.move == "shield" and SHIELD or RAISE
  elseif st == "fire" then n = FIRE
  elseif st == "shield" then n = SHIELD
  elseif st == "ring" or st == "close" then n = RING
  elseif st == "reel" then n = REEL end
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  if st == "shield" then                           -- the lamp shield: a ring of light, a bead a blow left
    circ(cx, cy, 24, f % 4 < 2 and C.lamp or C.marigold)
    for b = 1, s.count do circfill(cx - 8 + b * 4, s.y - 6, 1, C.lamp) end
  end
  if st == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.oxblood, C.glow) pal(C.marigold, C.glow) end
  sheet.load(SHEET)
  spr(n, math.floor(cx) - 24, math.floor(s.y + s.h) - 63, 6, 8, s.face < 0)
  sheet.load("actors.kolam")
  pal()
  if st == "wind" and s.move == "close" and stat("frame") % 4 < 2 then
    circ(cx, cy, B.close.r, C.vermil)              -- where the closing ring will come from
  end
  if st == "ring" or st == "close" then            -- the ring of fire going out, or closing in
    circ(cx, cy, s.ring, C.vermil)
    circ(cx, cy, s.ring - 1, C.lamp)
    for a = 0, 11 do
      local ang = a * 0.5236 + f * 0.1
      pset(cx + math.cos(ang) * (s.ring + 2), cy + math.sin(ang) * (s.ring + 2), C.saffron)
    end
  end
  for k = 1, NF do                                 -- her flames
    if fl[k] > 0 then
      circfill(fx_[k], fy[k], 3, C.red)
      circfill(fx_[k], fy[k], 2, C.saffron)
      pset(fx_[k], fy[k], C.glow)
      pset(fx_[k] - fvx[k] * 2, fy[k] - fvy[k] * 2 - f % 2, C.vermil)
    end
  end
end

shadows.kinds.rani = kind

return boss
