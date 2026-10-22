-- shadows.lua — the enemies: shadows of ink and paper.
--
--   shadows.add(x, y, kind)   feet at (x, y): "soldier", "dummy", "ink", "scrap"
--   shadows.update(body)      once a frame; strikes Komali through body.hurt
--   shadows.strike(s, n, dir, heavy)   Komali's blow: "hit", "blocked",
--                             "torn", or nil if it could not land
--   shadows.draw()
--   shadows.soft              a blow's cost is multiplied by this (a lesson
--                             room makes them soft)
--   shadows.kinds[kind]       { add, update, draw, strike, torn } for a kind
--                             made elsewhere (a story's shadows, its boss);
--                             one with fly set moves itself: no gravity
--   s.rally                   set on a shadow (the flag-bearer): the others
--                             within that many pixels take half of a blow
--   s.slow                    frames a shadow moves at half speed (an ink
--                             dart, shots.lua)
--   shadows.hard              hard mode: every shadow has half as much health
--                             again (and hits harder: body.lua)
--   shadows.shade             the room's boss is a shadow of his puppet (one
--                             saved already, or any in hard): s.shade is set
--                             on him, his moves are stronger, and he is drawn
--                             dark (shadows.dark)
--   shadows.lure              a decoy the shadows go for instead of Komali
--                             (the Minister's role): { x, y, w, h, hp, t,
--                             body }, lure.body standing in for body.lua;
--                             gone when its hp or its time (t) runs out
--
-- The cut-paper soldier walks up holding his guard to the front, so a
-- light blow from the front is turned aside; one from behind lands, and
-- so does a heavy one. When close he winds up (leaning back, flashing at
-- the end), strikes, and rests a moment: the time to hit him.
-- The straw dummy stands and takes blows, for learning on.
-- The inkblot crawls at Komali and hurts to touch; struck down the first
-- time, it splits into two small ones. The scrap, a torn paper bat, hangs
-- in the air and swoops at where Komali was.
-- Beaten, a shadow tears into scraps and leaves drops of ink (mai).

local move = require("move")
local fx   = require("fx")
local C    = require("colours")
local sound = require("sound")

local shadows = { list = {}, hits = 0, soft = 1, kinds = {}, hard = false, shade = false }

-- A shadow boss's colours: every colour to the dark of ink, the lightest
-- to the blue of a shadow on the night, the shades to ink.
local DARK = { [0] = 0, 1, 1, 47, 47, 15, 16, 16, 16, 47, 47, 15, 15, 16, 16, 47, 15, 16, 16, 15 }
function shadows.dark()
  for c = 0, 63 do pal(c, c < 20 and DARK[c] or c < 32 and 47 or 1) end
end

local S = {
  hp = 40,
  speed = 0.6,         -- walking, pixels a frame
  sight = 120,         -- how far off he sees Komali
  reach = 22,          -- how close he comes before winding up
  wind = 24,           -- frames of wind-up: the warning
  strike = 6,          -- frames the blow can land
  rest = 40,           -- frames after it, open to blows
  reel = 14,           -- frames knocked back by a blow that lands
  blow = 12,           -- what his blow costs Komali
  mai = { 1, 5 },      -- drops of ink he leaves
}
shadows.S = S
-- the others: health, what touching them costs, the mai they leave
local K = {
  dummy = { hp = 18, mai = { 1, 2 } },
  ink = { hp = 10, touch = 6, speed = 0.35, mai = { 1, 2 } },
  small = { hp = 5, touch = 4, speed = 0.5, mai = { 1, 1 } },
  scrap = { hp = 6, touch = 6, dive = 2.2, mai = { 1, 3 } },
}
shadows.K = K

-- Sprites in actors.png (see art.py): the soldier, 24x32, standing,
-- walking (four), winding up, striking, struck; the dummy, 24x32; the
-- inkblot's two frames (16x8) and the small one's (8x8); the scrap's three
-- (16x8).
local STAND, WALK, WIND, STRIKE, REEL = 512, 515, 527, 530, 533
local DUMMY, INK, SMALL, SCRAP = 768, 778, 782, 784

function shadows.add(x, y, kind)
  kind = kind or "soldier"
  local s = { kind = kind, x = x - 5, y = y - 20, w = 10, h = 20, vx = 0, vy = 0, face = -1,
              hp = kind == "soldier" and S.hp or K[kind] and K[kind].hp or 1,
              state = "walk", t = 0, landed = false, hit = 0, on = true, step = 0 }
  if kind == "ink" then
    s.y, s.w, s.h = y - 6, 12, 6
    -- the two it splits into, made now, asleep until then
    s.kids = {}
    for n = 1, 2 do
      local c = shadows.add(x, y, "small")
      c.on = false
      s.kids[n] = c
    end
  elseif kind == "small" then
    s.y, s.w, s.h, s.hp = y - 5, 6, 5, K.small.hp
  elseif kind == "scrap" then
    s.y, s.w, s.h, s.home = y - 6, 12, 6, y - 6
  elseif shadows.kinds[kind] then
    s.shade = shadows.shade                          -- (known to the boss's own add)
    shadows.kinds[kind].add(s)
    if s ~= shadows.boss then s.shade = nil end
  end
  if shadows.hard and kind ~= "dummy" then
    s.hp = s.hp * 3 // 2
    if s.max then s.max = s.hp end
  end
  shadows.list[#shadows.list + 1] = s
  return s
end

function shadows.clear()
  for n = #shadows.list, 1, -1 do shadows.list[n] = nil end
  shadows.lure = nil
end

-- is a shadow near a rallying one (not one itself)?
local function rallied(s)
  if s.rally then return false end
  for _, o in ipairs(shadows.list) do
    if o.on and o.rally and math.abs(o.x - s.x) < o.rally and math.abs(o.y - s.y) < 48 then return true end
  end
  return false
end
shadows.rallied = rallied

local function overlap(ax, ay, aw, ah, b)
  return ax < b.x + b.w and b.x < ax + aw and ay < b.y + b.h and b.y < ay + ah
end
shadows.overlap = overlap

-- touching Komali hurts (the inkblots and the scrap)
local function touch(s, body, n)
  if overlap(s.x, s.y, s.w, s.h, body.k) and body.hurt(math.max(1, math.floor(n * shadows.soft + 0.5)), s.x + s.w / 2) then
    shadows.hits = shadows.hits + 1
  end
end
shadows.touch = touch

local function soldier(s, body, k, dx)
  local st = s.state
  if st == "walk" then
    if math.abs(dx) < S.sight and math.abs(k.y - s.y) < 40 then
      s.face = dx < 0 and -1 or 1
      if math.abs(dx) > S.reach then
        -- walk on, but not off an edge
        local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
        s.vx = move.blocked(ahead, s.y + s.h, 1, 1) and s.face * S.speed or 0
      else
        s.vx, s.state, s.t = 0, "wind", S.wind
      end
    else
      s.vx = 0
    end
  elseif st == "wind" then
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t, s.landed = "strike", S.strike, false end
  elseif st == "strike" then
    local bx = s.face > 0 and s.x + s.w or s.x - 18
    if not s.landed and overlap(bx, s.y + 4, 18, 12, k) then
      if body.hurt(math.max(1, math.floor(S.blow * shadows.soft + 0.5)), s.x + s.w / 2) then
        s.landed = true
        shadows.hits = shadows.hits + 1
      end
    end
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "rest", S.rest end
  elseif st == "rest" or st == "reel" then
    s.t = s.t - 1
    if s.t <= 0 then s.state = "walk" end
  end
  if st ~= "walk" then s.vx = s.vx * 0.85 end
end

local function crawl(s, body, k, dx, c)
  if s.state == "reel" then
    s.t = s.t - 1
    s.vx = s.vx * 0.85
    if s.t <= 0 then s.state = "walk" end
  elseif math.abs(dx) < 140 and math.abs(k.y - s.y) < 40 then
    s.face = dx < 0 and -1 or 1
    local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
    s.vx = move.blocked(ahead, s.y + s.h, 1, 1) and s.face * c.speed or 0
  else
    s.vx = 0
  end
  touch(s, body, c.touch)
end

-- The scrap hangs, then swoops at where Komali was, and climbs back.
local function scrap(s, body, k, dx)
  local c = K.scrap
  if s.state == "walk" then
    s.vx, s.vy = 0, math.sin(s.step * 0.1) * 0.3
    s.step = s.step + 1
    if math.abs(dx) < 110 and k.y > s.y then
      s.state, s.t = "dive", 50
      local ex, ey = k.x + k.w / 2 - (s.x + s.w / 2), k.y + k.h / 2 - (s.y + s.h / 2)
      local len = math.max(1, math.sqrt(ex * ex + ey * ey))
      s.vx, s.vy = ex / len * c.dive, ey / len * c.dive
    end
  elseif s.state == "dive" then
    s.t = s.t - 1
    if s.t <= 0 then s.state = "rise" end
  else                                   -- climbing back (or knocked away)
    s.vx = s.vx * 0.9
    s.vy = s.y > s.home and -1 or 0
    if s.y <= s.home then s.state, s.t = "walk", 0 end
  end
  s.face = s.vx < 0 and -1 or 1
  s.x, s.y = s.x + s.vx, s.y + s.vy
  touch(s, body, c.touch)
end

function shadows.update(body)
  local lure = shadows.lure
  if lure then                                        -- a decoy: they go for it
    lure.t = lure.t - 1
    if lure.t <= 0 or lure.hp <= 0 then
      fx.tear(lure.x + lure.w / 2, lure.y + lure.h / 2, 0)
      shadows.lure = nil
    else
      body = lure.body
    end
  end
  local k = body.k
  local kx = k.x + k.w / 2
  for _, s in ipairs(shadows.list) do
    local x0 = s.x
    if s.on and math.abs(s.x - k.x) < 360 then        -- those far off sleep
      local dx = kx - (s.x + s.w / 2)
      local kind = s.kind
      if kind == "scrap" then
        scrap(s, body, k, dx)
      elseif shadows.kinds[kind] and shadows.kinds[kind].fly then
        shadows.kinds[kind].update(s, body, k, dx)
      else
        if kind == "soldier" then soldier(s, body, k, dx)
        elseif kind == "ink" or kind == "small" then crawl(s, body, k, dx, K[kind])
        elseif kind == "dummy" then s.vx = s.vx * 0.8
        elseif shadows.kinds[kind] then shadows.kinds[kind].update(s, body, k, dx) end
        s.vy = math.min(s.vy + 0.3, 5)
        local _, hy = move.by(s, s.vx, s.vy)
        if hy then s.vy = 0 end
        s.step = s.step + math.abs(s.vx)
      end
      if s == shadows.boss then                       -- a boss getting ready: the bell warns
        if s.state == "wind" and s.was ~= "wind" then sound.play("warn") end
        s.was = s.state
      end
      if (s.slow or 0) > 0 then                       -- inked: half as far across
        s.slow = s.slow - 1
        s.x = x0 + (s.x - x0) / 2
      end
    end
  end
end

local function tear(s, mai)
  s.on = false
  sound.play("torn")
  fx.tear(s.x + s.w / 2, s.y + s.h / 2, math.random(mai[1], mai[2]))
  if s.kids then                         -- an inkblot splits in two
    for n, c in ipairs(s.kids) do
      c.on, c.x, c.y, c.vx, c.vy, c.state = true, s.x + (n == 1 and 0 or 6), s.y + 1, n == 1 and -1.5 or 1.5, -2, "reel"
      c.t = 20
    end
  end
  local custom = shadows.kinds[s.kind]
  if custom and custom.torn then custom.torn(s) end
  return "torn"
end

function shadows.strike(s, n, dir, heavy)
  if not s.on then return nil end
  local custom = shadows.kinds[s.kind]
  if custom and custom.strike then
    local r = custom.strike(s, n, dir, heavy)
    if r ~= "hit" then return r end
  -- a light blow from the side he faces, while he is on guard, is turned aside
  elseif s.kind == "soldier" and not heavy and s.state == "walk" and dir == -s.face then
    fx.spark(s.x + s.w / 2 + s.face * 6, s.y + 10)
    s.vx = -s.face * 0.8
    return "blocked"
  end
  if rallied(s) then n = math.max(1, n // 2) end
  s.hp = s.hp - n
  if s.hp <= 0 then return tear(s, s.kind == "soldier" and S.mai or (K[s.kind] or custom).mai) end
  if s.kind == "soldier" then
    -- a heavy blow breaks his wind-up; a light one lands, but he strikes anyway
    if heavy or s.state == "walk" or s.state == "rest" then
      s.state, s.t = "reel", heavy and S.reel * 2 or S.reel
    end
  elseif s.kind == "scrap" then
    s.state = "rise"
  elseif s.kind ~= "dummy" and not custom then
    s.state, s.t = "reel", 12
  end
  if not custom then s.vx = dir * (heavy and 3 or 1.5) end
  return "hit"
end

function shadows.draw()
  local f = stat("frame")
  for _, s in ipairs(shadows.list) do
    if s.on and (s.slow or 0) > 0 then                -- inked: drips falling from it
      pset(s.x + s.w / 2 + (f // 6 % 3 - 1) * 3, s.y + s.h - 2 + f % 6, C.navy)
    end
    if s.on then
      local x, y, st, kind = math.floor(s.x), math.floor(s.y), s.state, s.kind
      if kind == "soldier" then
        local n = st == "wind" and WIND or st == "strike" and STRIKE or st == "reel" and REEL
                  or (math.abs(s.vx) > 0.1 and WALK + s.step // 6 % 4 * 3) or STAND
        if st == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.cloth, C.glow) pal(C.warm, C.glow) end   -- about to strike
        spr(n, x - 7, y - 12, 3, 4, s.face < 0)
        pal()
      elseif kind == "dummy" then
        spr(DUMMY, x - 7, y - 12, 3, 4)
      elseif kind == "ink" then
        spr(INK + (f // 12 % 2) * 2, x - 2, y - 2, 2, 1, s.face < 0)
      elseif kind == "small" then
        spr(SMALL + f // 8 % 2, x - 1, y - 3, 1, 1, s.face < 0)
      elseif kind == "scrap" then
        spr(SCRAP + f // 5 % 3 * 2, x - 2, y - 1, 2, 1, s.face < 0)
      elseif shadows.kinds[kind] then
        if s.shade then shadows.dark() end
        shadows.kinds[kind].draw(s)
        if s.shade then pal() end
      end
    end
  end
end

return shadows
