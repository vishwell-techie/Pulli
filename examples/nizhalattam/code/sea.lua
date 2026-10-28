-- sea.lua — the Leather Sea's own shadows, and its boats, added to
-- shadows.lua's kinds. rooms.lua requires it in the sea's rooms only, and
-- lets the code go when Komali leaves the story.
--
-- The crab-shield sidles at Komali with its great claw held up in front: a
-- light blow from the front is turned aside. Close, it draws back (the
-- warning) and lunges, then rests with the claw down, open to blows.
-- The wave-cutter waits on its wave; when it sees Komali the wave swells
-- (the warning) and it rides across the quay, through him, to the far end,
-- where the wave sinks and it rests. Riding, only a heavy blow reaches it.
-- The gull glides to and fro; with Komali below it cries, hovering (the
-- warning), then dives at where he was, and climbs back.
-- Boats float in the water between the quays: some bob where they are,
-- some drift to and fro across it. Komali stands on them (body.floors);
-- no blow touches them, and a fight room's door does not wait for them.

local shadows = require("shadows")
local body    = require("body")
local move    = require("move")
local fx      = require("fx")
local C       = require("colours")

local sea = { kinds = { "crab", "wave", "gull", "boat", "ferry" } }

local CR = { hp = 24, speed = 0.5, sight = 130, near = 40, wind = 22, lunge = 12, fast = 3.2, n = 10, rest = 50,
             mai = { 2, 4 } }
local WV = { hp = 20, sight = 200, wind = 24, speed = 2.2, n = 10, rest = 90, mai = { 2, 5 } }
local GL = { hp = 6, glide = 0.8, range = 48, sight = 160, wind = 20, dive = 3.0, n = 8, wait = 60, mai = { 1, 2 } }
local BT = { bob = 2.5, drift = 0.5 }
sea.CR, sea.WV, sea.GL = CR, WV, GL

-- Sprites in actors.png (see art.py): the crab-shield walking (two),
-- drawn back, lunging, resting (24x16); the wave-cutter riding (two) and
-- resting (32x16); the gull gliding, flapping, diving (16x8); the boat
-- (48x16).
local CRAB, WAVE, GULL, BOAT = 792, 920, 560, 932

local function ink(n) return math.max(1, math.floor(n * shadows.soft + 0.5)) end
local function flash(s) if s.state == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.cloth, C.glow) pal(C.red, C.glow) end end

-- ---- the crab-shield ----
local crab = { mai = CR.mai }

function crab.add(s)
  s.x, s.y, s.w, s.h = s.x - 5, s.y + 8, 20, 12
  s.hp = CR.hp
end

function crab.update(s, body_, k, dx)
  local st = s.state
  if st == "walk" then
    if math.abs(dx) < CR.sight and math.abs(k.y - s.y) < 40 then
      s.face = dx < 0 and -1 or 1
      if math.abs(dx) > CR.near then
        local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
        s.vx = move.blocked(ahead, s.y + s.h, 1, 1) and s.face * CR.speed or 0
      else
        s.vx, s.state, s.t = 0, "wind", CR.wind
      end
    else
      s.vx = 0
    end
  elseif st == "wind" then
    s.vx, s.t = 0, s.t - 1
    if s.t <= 0 then s.state, s.t, s.landed = "lunge", CR.lunge, false end
  elseif st == "lunge" then
    local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
    s.vx = move.blocked(ahead, s.y + s.h, 1, 1) and s.face * CR.fast or 0
    if not s.landed and shadows.overlap(s.x + s.face * 6, s.y, s.w, s.h, k) and body_.hurt(ink(CR.n), s.x + s.w / 2) then
      s.landed = true
      shadows.hits = shadows.hits + 1
    end
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.t = "rest", CR.rest end
  else                                             -- resting, or reeling
    s.vx, s.t = s.vx * 0.85, s.t - 1
    if s.t <= 0 then s.state = "walk" end
  end
end

-- the claw turns a light blow from the front while it walks or draws back
function crab.strike(s, n, dir, heavy)
  if not heavy and dir == -s.face and (s.state == "walk" or s.state == "wind") then
    fx.spark(s.x + s.w / 2 + s.face * 10, s.y + 4)
    s.vx = -s.face * 0.8
    return "blocked"
  end
  if heavy or s.state == "walk" then s.state, s.t = "reel", heavy and 24 or 12 end
  s.vx = dir * (heavy and 2.5 or 1.2)
  return "hit"
end

function crab.draw(s)
  local st = s.state
  local n = st == "wind" and 2 or st == "lunge" and 3 or (st == "rest" or st == "reel") and 4 or s.step // 6 % 2
  flash(s)
  spr(CRAB + n * 3, math.floor(s.x) - 2, math.floor(s.y) - 4, 3, 2, s.face < 0)
  pal()
end

-- ---- the wave-cutter ----
local wave = { mai = WV.mai }

function wave.add(s)
  s.x, s.y, s.w, s.h = s.x - 7, s.y + 8, 24, 12
  s.hp, s.state, s.t = WV.hp, "rest", 30
end

function wave.update(s, body_, k, dx)
  local st = s.state
  if st == "walk" then                             -- waiting on its wave
    s.vx = 0
    if math.abs(dx) < WV.sight and math.abs(k.y - s.y) < 48 then
      s.face, s.state, s.t = dx < 0 and -1 or 1, "wind", WV.wind
    end
  elseif st == "wind" then
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.landed = "ride", false end
  elseif st == "ride" then
    -- across, through him, on to a wall or the edge of the quay
    local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
    if move.blocked(ahead, s.y, 1, s.h - 2) or not move.blocked(ahead, s.y + s.h, 1, 1) then
      s.state, s.t, s.vx = "rest", WV.rest, 0
    else
      s.vx = s.face * WV.speed
    end
    if not s.landed and shadows.overlap(s.x, s.y, s.w, s.h, k) and body_.hurt(ink(WV.n), s.x + s.w / 2) then
      s.landed = true
      shadows.hits = shadows.hits + 1
    end
  else                                             -- the wave sunk: resting, or reeling
    s.vx, s.t = s.vx * 0.8, s.t - 1
    if s.t <= 0 then s.state = "walk" end
  end
end

-- riding, only a heavy blow reaches it
function wave.strike(s, n, dir, heavy)
  if s.state == "ride" and not heavy then
    fx.spark(s.x + s.w / 2, s.y + 2)
    return "blocked"
  end
  if s.state ~= "ride" then s.state, s.t = "reel", math.max(s.t, 20) end
  return "hit"
end

function wave.draw(s)
  local n = (s.state == "ride" or s.state == "wind") and stat("frame") // 8 % 2 or 2
  flash(s)
  spr(WAVE + n * 4, math.floor(s.x) - 4, math.floor(s.y) - 4, 4, 2, s.face < 0)
  pal()
end

-- ---- the gull ----
local gull = { mai = GL.mai, fly = true }

function gull.add(s)
  s.x, s.y, s.w, s.h = s.x - 1, s.y + 12, 12, 6
  s.hp, s.home, s.home_x, s.vx, s.wait = GL.hp, s.y, s.x, GL.glide, 0
end

function gull.update(s, body_, k, dx)
  local st, dy = s.state, k.y + k.h / 2 - (s.y + s.h / 2)
  if s.wait > 0 then s.wait = s.wait - 1 end
  if st == "walk" then                             -- gliding to and fro over home
    if (s.vx > 0 and s.x > s.home_x + GL.range) or (s.vx < 0 and s.x < s.home_x - GL.range)
       or move.blocked(s.x + (s.vx > 0 and s.w or -1), s.y, 1, s.h) then s.vx = -s.vx end
    s.vy = math.sin(s.step * 0.08) * 0.3
    if s.wait == 0 and math.abs(dx) < 70 and dy > 20 and dy < GL.sight then
      s.state, s.t, s.vx, s.vy = "wind", GL.wind, 0, 0
    end
  elseif st == "wind" then                         -- hovering, crying out
    s.t = s.t - 1
    s.face = dx < 0 and -1 or 1
    if s.t <= 0 then
      local len = math.max(1, math.sqrt(dx * dx + dy * dy))
      s.state, s.t, s.vx, s.vy = "dive", 60, dx / len * GL.dive, dy / len * GL.dive
    end
  elseif st == "dive" then
    s.t = s.t - 1
    if s.t <= 0 or move.blocked(s.x, s.y + s.h, s.w, 1) then s.state = "rise" end
  else                                             -- climbing back (or knocked away)
    s.vx = s.vx * 0.9
    s.vy = s.y > s.home and -1 or 0
    if s.y <= s.home then
      s.state, s.wait, s.vx = "walk", GL.wait, s.x < s.home_x and GL.glide or -GL.glide
    end
  end
  if st ~= "wind" and math.abs(s.vx) > 0.05 then s.face = s.vx < 0 and -1 or 1 end
  s.step = s.step + 1
  s.x, s.y = s.x + s.vx, s.y + s.vy
  if st == "dive" then shadows.touch(s, body_, GL.n) end
end

function gull.strike(s, n, dir)
  s.state, s.vx = "rise", dir * 2
  return "hit"
end

function gull.draw(s)
  local st = s.state
  local n = st == "dive" and 2 or (st == "wind" or st == "rise") and stat("frame") // 4 % 2 or 0
  if st == "wind" and s.t % 6 < 3 then pal(C.cloth, C.glow) pal(C.silver, C.lamp) end
  spr(GULL + n * 2, math.floor(s.x) - 2, math.floor(s.y) - 1, 2, 1, s.face < 0)
  pal()
end

-- ---- boats ----
-- A boat's top, where Komali stands, is level with the quays (the marker's
-- feet); it bobs on the swell. A ferry drifts too, to and fro between them.
local boat = { fly = true }

function boat.add(s)
  s.home = s.y + s.h
  s.x, s.y, s.w, s.h = s.x - 15, s.home, 40, 10
  s.dx, s.dy, s.prop = 0, 0, true
  s.vx = s.kind == "ferry" and BT.drift or 0
  local fl = body.floors
  fl[#fl + 1] = s
end

function boat.update(s)
  local x, y = s.x, s.y
  s.step = s.step + 1
  if s.vx ~= 0 then
    local ahead = s.vx > 0 and s.x + s.w + 4 or s.x - 5
    if move.blocked(ahead, s.y + 3, 1, 6) then s.vx = -s.vx end
    s.x = s.x + s.vx
  end
  s.y = s.home + math.sin(s.step * 0.05) * BT.bob
  s.dx, s.dy = s.x - x, s.y - y
end

function boat.strike() return nil end

function boat.draw(s)
  spr(BOAT, math.floor(s.x) - 4, math.floor(s.y) - 6, 6, 2)
end

shadows.kinds.crab, shadows.kinds.wave, shadows.kinds.gull = crab, wave, gull
shadows.kinds.boat, shadows.kinds.ferry = boat, boat

return sea
