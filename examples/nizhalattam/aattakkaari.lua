-- aattakkaari.lua — Aattakkaari, the dancer, the Leather Sea's boss: a
-- captured puppet wearing the role the Puppet King forced on her.
--
--   require("aattakkaari")   adds the kind "aattakkaari" to shadows.lua;
--                            rooms.lua does this on her deck only
--   shadows.boss             the boss in the room; shadows.beaten is set
--                            when she is torn, and main.lua lends her role
--
-- She dances across the deck. Rising on her toes, her anklet bells
-- ringing, she comes in spinning kicks, each a hop toward Komali. Crouched
-- low, the bells ringing, she dashes the deck's length: a dash that lands
-- stuns him (A, Y or B shake it off sooner). Come too close and she
-- whirls, striking all round; stay close, and she dashes through him. The first time she does a move its warning
-- is twice as long. After each she rests, open to blows; a heavy blow while
-- she walks or gets ready breaks it off. Below half her health she rests
-- less and kicks once more. Twice Komali's size: no single jump clears her.
--
-- Her shadow (s.shade: once she is saved, or in hard mode) leaves
-- afterimages: each kick, whirl and dash is left behind as a dark copy of
-- her, which strikes again where it was, a beat later.

local shadows = require("shadows")
local move    = require("move")
local fx      = require("fx")
local C       = require("colours")

local boss = { kinds = { "aattakkaari" } }

local B = {
  hp = 170,
  w = 20, h = 40,
  speed = 0.9,
  near = 44,                                       -- closer than this, she whirls
  far = 120,                                       -- further than this, she dances closer
  wind = { kicks = 26, dash = 30, whirl = 14 },    -- frames of warning (twice the first time)
  kicks = { count = 3, hop = 2.6, gap = 22, n = 12, w = 22, h = 20 },
  dash = { speed = 5, n = 14, stun = 40, most = 70 },
  whirl = { frames = 18, n = 12, r = 34 },
  rest = { kicks = 50, dash = 60, whirl = 36 },
  echo = { beat = 28, frames = 8, n = 10 },        -- (the shadow's) afterimages
  mai = { 40, 50 },
  oil = 10,
  role = "aattakkaari",                            -- the role she lends, beaten
}
boss.B = B

-- Sprites in aatta.kolam (48x64, see art.py): on guard, walking (four),
-- rising, kicking, spinning, crouching, dashing; the whirl and struck in
-- the second row.
local SHEET = "aatta.kolam"
local GUARD, WALK, RISE, KICK, SPIN, CROUCH, DASH, WHIRL, REEL = 0, 6, 30, 36, 42, 48, 54, 512, 518

-- the shadow's afterimages: a few long arrays (the box the blow covers,
-- where she stood and the frame drawn, frames until it is gone, and
-- whether it has struck)
local NE = 4
local ex, ey, ew, eh, ecx, efeet, eface, eframe, et, egot = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
for n = 1, NE do et[n] = 0 end
local function echo(s, x, y, w, h, frame)
  for n = 1, NE do
    if et[n] <= 0 then
      ex[n], ey[n], ew[n], eh[n], ecx[n], efeet[n] = x, y, w, h, s.x + s.w / 2, s.y + s.h
      eface[n], eframe[n], et[n], egot[n] = s.face, frame, B.echo.beat + B.echo.frames, false
      return
    end
  end
end

local kind = { mai = B.mai }

function kind.add(s)
  for n = 1, NE do et[n] = 0 end
  s.x, s.y, s.w, s.h = s.x + 5 - B.w / 2, s.y + 20 - B.h, B.w, B.h
  s.hp, s.max, s.shown, s.think, s.turn = B.hp, B.hp, {}, 50, 0
  s.oil, s.role = B.oil, B.role
  shadows.boss, shadows.beaten = s, false
end

local function hurt(s, body, k, n, x, y, w, h)
  if not s.landed and shadows.overlap(x, y, w, h, k) and body.hurt(n, s.x + s.w / 2) then
    s.landed = true
    shadows.hits = shadows.hits + 1
    return true
  end
end

function kind.update(s, body, k, dx)
  local st = s.state
  local tired = s.hp < s.max / 2
  if st == "walk" then
    s.face = dx < 0 and -1 or 1
    local dist = math.abs(dx)
    s.vx = dist > B.far and s.face * B.speed or 0
    s.think = s.think - 1
    if dist < B.near or s.think <= 0 then
      -- close, a whirl; but never two running: then she dashes through
      local m = s.move ~= "whirl" and "whirl" or "dash"
      if dist >= B.near then s.turn = s.turn + 1; m = s.turn % 2 == 1 and "kicks" or "dash" end
      -- the dash goes toward him, unless a wall is close that way
      if m == "dash" and move.blocked(s.face > 0 and s.x + s.w or s.x - 48, s.y, 48, s.h - 2) then s.face = -s.face end
      s.move, s.state, s.vx = m, "wind", 0
      s.t = B.wind[m] * (s.shown[m] and 1 or 2)
      s.shown[m] = true
    end
  elseif st == "wind" then
    s.vx = 0
    if s.move ~= "dash" then s.face = dx < 0 and -1 or 1 end
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t, s.count, s.landed, s.from = s.move, 0, 0, false, s.x end
  elseif st == "kicks" then
    -- a hop toward him with each kick; the kick lands in front of her
    local K = B.kicks
    if s.t % K.gap == 0 then
      s.face = dx < 0 and -1 or 1
      s.vx, s.vy, s.landed = s.face * K.hop, -2, false
      s.count = s.count + 1
    end
    s.t = s.t + 1
    if s.t % K.gap > 4 and s.t % K.gap < 16 then
      hurt(s, body, k, K.n, s.face > 0 and s.x + s.w or s.x - K.w, s.y + 8, K.w, K.h)
    end
    if s.shade and s.t % K.gap == 8 then echo(s, s.face > 0 and s.x + s.w or s.x - K.w, s.y + 8, K.w, K.h, KICK) end
    if s.count >= K.count + (tired and 1 or 0) and s.t % K.gap == 0 then
      s.state, s.t, s.vx = "rest", math.floor(B.rest.kicks * (tired and 0.7 or 1)), 0
    end
  elseif st == "dash" then
    -- the deck's length, through him; it ends at a wall
    local D = B.dash
    s.t = s.t + 1
    local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
    if move.blocked(ahead, s.y, 1, s.h - 2) or s.t > D.most then
      if s.shade then
        local a, b = math.min(s.from, s.x), math.max(s.from, s.x) + s.w
        echo(s, a, s.y + 8, b - a, s.h - 8, DASH)
      end
      s.state, s.t, s.vx = "rest", math.floor(B.rest.dash * (tired and 0.7 or 1)), 0
    else
      s.vx = s.face * D.speed
      if hurt(s, body, k, D.n, s.x, s.y, s.w, s.h) then k.held = D.stun end
    end
  elseif st == "whirl" then
    local W = B.whirl
    s.t = s.t + 1
    if s.shade and s.t == 1 then echo(s, s.x + s.w / 2 - W.r, s.y + 4, W.r * 2, s.h - 4, WHIRL) end
    hurt(s, body, k, W.n, s.x + s.w / 2 - W.r, s.y + 4, W.r * 2, s.h - 4)
    if s.t >= W.frames then s.state, s.t = "rest", math.floor(B.rest.whirl * (tired and 0.7 or 1)) end
  elseif st == "rest" or st == "reel" then
    s.vx = s.vx * 0.85
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.think = "walk", tired and 24 or 40 end
  end
  -- the afterimages: each strikes once, a beat after the blow it copies
  for n = 1, NE do
    if et[n] > 0 then
      et[n] = et[n] - 1
      if et[n] < B.echo.frames and not egot[n]
         and shadows.overlap(ex[n], ey[n], ew[n], eh[n], k) and body.hurt(B.echo.n, ex[n] + ew[n] / 2) then
        shadows.hits = shadows.hits + 1
        egot[n] = true
      end
    end
  end
end

-- No guard; a heavy blow while she walks or gets ready breaks it off.
function kind.strike(s, n, dir, heavy)
  if heavy and (s.state == "walk" or s.state == "wind") then s.state, s.t, s.vx = "reel", 16, dir * 1.5 end
  return "hit"
end

function kind.torn(s)
  shadows.beaten = true
  for n = 1, NE do et[n] = 0 end
  fx.tear(s.x + s.w / 2, s.y + 4, 0)
  fx.tear(s.x + s.w / 2, s.y + 16, 0)
end

function kind.draw(s)
  local x, y, st, f = math.floor(s.x + s.w / 2) - 24, math.floor(s.y + s.h) - 63, s.state, stat("frame")
  local n = GUARD
  if st == "walk" then n = math.abs(s.vx) > 0.1 and WALK + s.step // 6 % 4 * 6 or GUARD
  elseif st == "wind" then n = s.move == "dash" and CROUCH or s.move == "whirl" and WHIRL or RISE
  elseif st == "kicks" then n = s.t % B.kicks.gap < 6 and SPIN or KICK
  elseif st == "dash" then n = DASH
  elseif st == "whirl" then n = f // 3 % 2 == 0 and WHIRL or SPIN
  elseif st == "reel" then n = REEL end
  -- getting ready, her anklet bells ring: sparks at her feet
  if st == "wind" then
    for b = 0, 2 do pset(s.x + s.w / 2 - 6 + b * 6 + (f + b) % 3 - 1, s.y + s.h - 3 - (f // 2 + b) % 3, C.lamp) end
  end
  -- the dash leaves streaks behind her; the whirl a ring
  if st == "dash" then
    for d = 1, 3 do line(s.x + s.w / 2 - s.face * (12 + d * 8), s.y + 10 + d * 7, s.x + s.w / 2 - s.face * (24 + d * 10),
                         s.y + 10 + d * 7, C.marigold) end
  elseif st == "whirl" then
    circ(s.x + s.w / 2, s.y + s.h / 2, B.whirl.r - (f % 4), C.lamp)
  end
  sheet.load(SHEET)
  -- her afterimages: dim while they wait, whole as they strike
  for e = 1, NE do
    if et[e] > 0 and (et[e] < B.echo.frames or f % 3 > 0) then
      spr(eframe[e], math.floor(ecx[e]) - 24, math.floor(efeet[e]) - 63, 6, 8, eface[e] < 0)
      if eframe[e] == DASH then                       -- the path the dash will take again
        for d = 0, ew[e], 6 do pset(ex[e] + d, ey[e] + eh[e] // 2 + (d // 6 + f // 2) % 2, C.sky) end
      end
    end
  end
  if st == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.vermil, C.glow) pal(C.marigold, C.glow) end
  spr(n, x, y, 6, 8, s.face < 0)
  sheet.load("actors.kolam")
  pal()
end

shadows.kinds.aattakkaari = kind

return boss
