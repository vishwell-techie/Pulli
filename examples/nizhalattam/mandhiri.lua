-- mandhiri.lua — the Minister (Mandhiri), the Market of Masks' boss: a
-- captured puppet wearing the role the Puppet King forced on him.
--
--   require("mandhiri")      adds the kinds "mandhiri" and "decoy" to
--                            shadows.lua; rooms.lua does this in his court only
--   shadows.boss             the boss in the room; shadows.beaten is set
--                            when he is torn, and main.lua lends his role
--
-- He schemes from afar, stepping back when Komali comes close. He throws an
-- ink dart at Komali (he draws back his arm, the warning). He tosses three
-- ink snares to land about Komali: stepping on one holds him (A, Y or B
-- shake it off sooner). Or he conjures two paper decoys of himself, and
-- every so often he and they change places in a puff of smoke: a blow
-- tears a decoy, and only the real one drips ink. The first time he does a
-- move its warning is twice as long. Below half his health he rests less.

local shadows = require("shadows")
local fight   = require("fight")
local move    = require("move")
local fx      = require("fx")
local C       = require("colours")

local boss = { kinds = { "mandhiri", "decoy" } }

local B = {
  hp = 170,
  w = 20, h = 40,
  speed = 0.7,
  near = 56,                                       -- closer than this, he steps back
  far = 150,                                       -- further than this, he comes closer
  wind = { dart = 22, snare = 28, decoys = 34 },   -- frames of warning (twice the first time)
  dart = { n = 10, speed = 3.4, life = 110 },
  snare = { count = 3, spread = 30, flight = 30, hold = 50, n = 4, life = 420 },
  decoys = { life = 480, shuffle = 80 },
  rest = { dart = 40, snare = 50, decoys = 40 },
  mai = { 45, 55 },
  oil = 11,
  role = "mandhiri",                               -- the role he lends, beaten
}
boss.B = B

-- Sprites in mandhiri.kolam (48x64, see art.py): on guard, walking (four),
-- throwing, tossing, conjuring, struck.
local SHEET = "mandhiri.kolam"
local GUARD, WALK, THROW, TOSS, CONJURE, REEL = 0, 6, 30, 36, 42, 48

-- his snares: a few long arrays (where, where to, frames left)
local NS = 3
local sx, sy, sx0, sy0, stx, sty, sf, sl = {}, {}, {}, {}, {}, {}, {}, {}
for n = 1, NS do sx[n], sy[n], sx0[n], sy0[n], stx[n], sty[n], sf[n], sl[n] = 0, 0, 0, 0, 0, 0, 0, 0 end

local kind = { mai = B.mai }
local decoy = { mai = { 0, 0 } }                   -- paper: nothing in it

function kind.add(s)
  s.x, s.y, s.w, s.h = s.x + 5 - B.w / 2, s.y + 20 - B.h, B.w, B.h
  s.hp, s.max, s.shown, s.think, s.turn = B.hp, B.hp, {}, 50, 0
  s.oil, s.role, s.ax, s.ay, s.dl = B.oil, B.role, 0, 0, 0
  shadows.boss, shadows.beaten = s, false
  for n = 1, NS do sl[n] = 0 end
  -- the two decoys, made now, put away until he conjures them
  s.decoys = {}
  for n = 1, 2 do
    local d = shadows.add(s.x + B.w / 2, s.y + B.h, "decoy")
    d.on, d.real = false, s
    s.decoys[n] = d
  end
end

local function hand(s) return s.x + s.w / 2 + s.face * 12, s.y + 10 end

function kind.update(s, body, k, dx)
  local st = s.state
  local tired = s.hp < s.max / 2 and 0.7 or 1
  if st == "walk" then
    s.face = dx < 0 and -1 or 1
    local dist, go = math.abs(dx), 0
    if dist < B.near then go = -s.face elseif dist > B.far then go = s.face end
    local ahead = go > 0 and s.x + s.w + 1 or s.x - 2
    s.vx = (go ~= 0 and not move.blocked(ahead, s.y, 1, s.h - 2)) and go * B.speed or 0
    s.think = s.think - 1
    if s.think <= 0 then
      s.turn = s.turn + 1
      local m = ({ "dart", "snare", "decoys" })[(s.turn - 1) % 3 + 1]
      if m == "decoys" and s.decoys[1].on then m = "dart" end   -- they are out already
      s.move, s.state, s.vx = m, "wind", 0
      s.t = B.wind[m] * (s.shown[m] and 1 or 2)
      s.shown[m] = true
    end
  elseif st == "wind" then
    s.vx = 0
    s.face = dx < 0 and -1 or 1
    local hx, hy = hand(s)
    local ex, ey = k.x + k.w / 2 - hx, k.y + k.h / 2 - hy
    local len = math.max(1, math.sqrt(ex * ex + ey * ey))
    s.ax, s.ay = ex / len, ey / len
    s.t = s.t - 1
    if s.t <= 0 then
      local m = s.move
      if m == "dart" and fight.shots then
        fight.shots.fire(hx, hy, s.ax * B.dart.speed, s.ay * B.dart.speed, B.dart.life, B.dart.n, false, false, true)
      elseif m == "snare" then                     -- three blots lobbed to land about him
        local floor = s.y + s.h
        for n = 1, NS do
          sx0[n], sy0[n], sx[n], sy[n] = hx, hy, hx, hy
          stx[n], sty[n] = k.x + k.w / 2 + (n - 2) * B.snare.spread, floor
          sf[n], sl[n] = B.snare.flight, B.snare.life
        end
      elseif m == "decoys" then                    -- two paper Ministers, either side
        for n, d in ipairs(s.decoys) do
          d.on, d.hp, d.state, d.t, d.face = true, 1, "walk", B.decoys.shuffle, s.face
          d.x, d.y, d.life = s.x + (n == 1 and -64 or 64), s.y, B.decoys.life
          if move.blocked(d.x, d.y, d.w, d.h - 2) then d.x = s.x + (n == 1 and 32 or -32) end
          fx.tear(d.x + d.w / 2, d.y + 10, 0)
        end
      end
      s.state, s.t = "act", 14
    end
  elseif st == "act" then
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "rest", math.floor(B.rest[s.move] * tired) end
  elseif st == "rest" or st == "reel" then
    s.vx = s.vx * 0.85
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.think = "walk", math.floor(40 * tired) end
  end
  -- the snares: in flight, then lying in wait
  for n = 1, NS do
    if sl[n] > 0 then
      sl[n] = sl[n] - 1
      if sf[n] > 0 then
        sf[n] = sf[n] - 1
        local t = 1 - sf[n] / B.snare.flight
        sx[n] = sx0[n] + (stx[n] - sx0[n]) * t
        sy[n] = sy0[n] + (sty[n] - sy0[n]) * t - math.sin(t * math.pi) * 40
      elseif k.held == 0 and math.abs(k.x + k.w / 2 - sx[n]) < 8 and math.abs(k.y + k.h - sy[n]) < 3 then
        if body.hurt(B.snare.n, sx[n]) then shadows.hits = shadows.hits + 1 end
        k.held, k.vx, sl[n] = B.snare.hold, 0, 0
      end
    end
  end
  -- the ink he drips: the tell among the decoys
  s.dl = (s.dl + 1) % 24
end

-- No guard; a heavy blow while he walks or gets ready breaks it off.
function kind.strike(s, n, dir, heavy)
  if heavy and (s.state == "walk" or s.state == "wind") then s.state, s.t, s.vx = "reel", 16, dir * 1.5 end
  return "hit"
end

function kind.torn(s)
  shadows.beaten = true
  fx.tear(s.x + s.w / 2, s.y + 4, 0)
  fx.tear(s.x + s.w / 2, s.y + 16, 0)
  for _, d in ipairs(s.decoys) do d.on = false end
  for n = 1, NS do sl[n] = 0 end
end

local function draw_minister(s, n)
  sheet.load(SHEET)
  spr(n, math.floor(s.x + s.w / 2) - 24, math.floor(s.y + s.h) - 63, 6, 8, s.face < 0)
  sheet.load("actors.kolam")
end

local function frame_of(s)
  local st = s.state
  if st == "walk" then return math.abs(s.vx) > 0.1 and WALK + s.step // 6 % 4 * 6 or GUARD end
  if st == "wind" then return s.move == "decoys" and CONJURE or s.move == "snare" and TOSS or THROW end
  if st == "act" then return s.move == "decoys" and CONJURE or s.move == "snare" and TOSS or THROW end
  if st == "reel" then return REEL end
  return GUARD
end

function kind.draw(s)
  if s.state == "wind" and s.move == "dart" then             -- where the dart will go
    local hx, hy = hand(s)
    for d = 1, 6 do
      if (d + stat("frame") // 3) % 2 == 0 then pset(hx + s.ax * d * 12, hy + s.ay * d * 12, C.navy) end
    end
  end
  if s.state == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.cloth, C.glow) pal(C.marigold, C.glow) end
  draw_minister(s, frame_of(s))
  pal()
  -- he drips ink; his paper decoys do not
  local hx = s.x + s.w / 2 - s.face * 4
  if s.dl < 12 then pset(hx, s.y + 22 + s.dl, C.navy) else pset(hx, s.y + s.h - 1, C.ink) end
  for n = 1, NS do                                 -- the snares, in flight or lying in wait
    if sl[n] > 0 then
      if sf[n] > 0 then
        circfill(sx[n], sy[n], 2, C.navy)
      else
        local w = sl[n] < 60 and stat("frame") % 4 < 2 and 0 or 1
        rectfill(sx[n] - 6, sy[n] - 2, 13, 2, C.ink)
        line(sx[n] - 4, sy[n] - 3, sx[n] + 4, sy[n] - 3, C.navy)
        if w == 1 then pset(sx[n] - 2, sy[n] - 3, C.blue) pset(sx[n] + 3, sy[n] - 4, C.blue) end
      end
    end
  end
end

-- ---- a paper decoy: walks as he does; one blow and it is gone; every so
-- often, he and a decoy change places in a puff ----
function decoy.add(s)
  s.w, s.h = B.w, B.h
  s.y = s.y - (B.h - 20)
  s.x = s.x + 5 - B.w / 2
  s.hp = 1
end

function decoy.update(s, body, k, dx)
  local real = s.real
  s.life = s.life - 1
  if s.life <= 0 or not real.on then
    s.on = false
    fx.tear(s.x + s.w / 2, s.y + 10, 0)
    return
  end
  s.face = dx < 0 and -1 or 1
  s.state = real.state == "rest" and "walk" or real.state
  s.move, s.step = real.move, real.step
  local go = math.abs(dx) < B.near and -s.face or 0
  local ahead = go > 0 and s.x + s.w + 1 or s.x - 2
  s.vx = (go ~= 0 and not move.blocked(ahead, s.y, 1, s.h - 2)) and go * B.speed or 0
  s.t = s.t - 1
  if s.t <= 0 then                                 -- change places with him
    s.t = B.decoys.shuffle + (s == real.decoys[1] and 0 or B.decoys.shuffle // 2)
    if real.state == "walk" or real.state == "rest" then
      s.x, real.x = real.x, s.x
      fx.tear(s.x + s.w / 2, s.y + 10, 0)
      fx.tear(real.x + real.w / 2, real.y + 10, 0)
    end
  end
end

function decoy.strike(s) return "hit" end

function decoy.draw(s)
  draw_minister(s, frame_of(s))
end

shadows.kinds.mandhiri, shadows.kinds.decoy = kind, decoy

return boss
