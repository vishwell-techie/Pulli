-- king.lua — the Puppet King, at the end of the Lamp Palace: a fight in
-- three acts, a room each (the room says which: def.act).
--
--   require("king")          adds the kind "king" to shadows.lua; rooms.lua
--                            does this on his stage only
--   shadows.boss             the King; shadows.beaten is set when he is
--                            beaten in an act. s.act says which; after the
--                            third, main.lua has him let a puppet go.
--
-- Act one: he swings his sceptre wide, sweeps up his cape (blows from the
--   front are turned back on Komali while it is up), and calls soldiers in
--   from the wings.
-- Act two: lamps fall from above (a shadow on the floor where each will
--   land), and he throws his crown, which flies out and comes back.
-- Act three: he fights with the moves he has taken, one from each puppet
--   saved (STORY.md): the warrior's leaping slash, the archer's volley, the
--   dancer's dash, the elephant's pound, the minister's snare, the queen's
--   ring of fire. With none saved the act is short.
-- Each move shows a warning first, twice as long the first time.
--
-- In hard mode, with the King home, it is his shadow that waits here
-- (s.shade), the last of the anger he was painted with: the first two acts
-- have two puppets' moves each as well as their own, the third all six (all
-- are saved by then), his lamps fall twice as
-- often, and when he summons, with his soldiers comes a puppet's shadow,
-- each in turn, which steps out of the wings, does its puppet's move once
-- (a dash across the stage, or three shots), and tears away. Beaten in the
-- third act, it brings Ending B (main.lua).

local shadows = require("shadows")
local fight   = require("fight")
local run     = require("run")
local move    = require("move")
local fx      = require("fx")
local C       = require("colours")
local sound   = require("sound")

local boss = { kinds = { "king" } }

local B = {
  hp = { 120, 120, 70 }, more = 25,                -- act three: more for each puppet saved
  w = 20, h = 40,
  speed = 0.7, near = 44, far = 120,
  wind = { swing = 18, cape = 14, summon = 30, crown = 24, leap = 20, volley = 26, dash = 28, pound = 26,
           snare = 24, ring = 20 },
  swing = { n = 14, w = 34, h = 26 },
  cape = { frames = 60, back = 6 },               -- up so long; a blow into it costs Komali this
  crown = { speed = 4, out = 34, n = 12 },
  lamps = { every = 70, warn = 40, n = 12 },
  leap = { up = 4.6, across = 2.6, n = 16 },
  volley = { count = 3, gap = 12, n = 8, speed = 3.2, life = 100 },
  dash = { speed = 5, n = 14, most = 70 },
  pound = { n = 12, speed = 3.2, life = 80, high = 8 },
  snare = { hold = 50, n = 4, life = 300 },
  ring = { r = 64, frames = 36, n = 12 },
  rest = 40,
  shade_lamps = 40,                                -- (the shadow's) lamps fall this often
  puppet = { wait = 30, life = 140, gap = 14, count = 3, speed = 3.2, shot_life = 110 },
  mai = { 60, 70 },
  oil = 25,
}
boss.B = B
-- the move each puppet saved lends him in the third act
local TAKEN = { veeran = "leap", vil = "volley", aattakkaari = "dash", yaanai = "pound", mandhiri = "snare",
                rani = "ring" }
local PUPPETS = { "veeran", "vil", "aattakkaari", "yaanai", "mandhiri", "rani" }
-- a puppet's shadow, summoned by the King's: its sheet, the frame of its
-- move, its size in cells, and the move: a dash (speed, blow) or shots
-- (blow; an ink dart for the Minister)
local SHADE = {
  veeran = { sheet = "actors.kolam", frame = 1072, w = 6, dash = 2.6, n = 12 },
  vil = { sheet = "vil.kolam", frame = 36, w = 6, n = 10 },
  aattakkaari = { sheet = "aatta.kolam", frame = 54, w = 6, dash = 5, n = 14 },
  yaanai = { sheet = "yaanai.kolam", frame = 48, w = 8, dash = 4.2, n = 16 },
  mandhiri = { sheet = "mandhiri.kolam", frame = 30, w = 6, n = 10, ink = true },
  rani = { sheet = "rani.kolam", frame = 36, w = 6, n = 10 },
}
boss.SHADE = SHADE

-- Sprites in king.kolam (48x64, see art.py): on guard, walking (four),
-- raising the sceptre, the swing, the cape, the throw; the leap, the
-- pound and struck in the second row.
local SHEET = "king.kolam"
local GUARD, WALK, RAISE, SWING, CAPE, THROW, LEAP, POUND, REEL = 0, 6, 30, 36, 42, 48, 54, 512, 518

local kind = { mai = B.mai }

function kind.add(s)
  local act = require("rooms").def().act or 1
  s.x, s.y, s.w, s.h = s.x + 5 - B.w / 2, s.y + 20 - B.h, B.w, B.h
  s.act, s.shown, s.think, s.turn, s.wt, s.ring, s.lamp = act, {}, 60, 0, 0, 0, B.lamps.every
  s.moves = act == 1 and { "swing", "cape", "summon" } or act == 2 and { "swing", "crown", "cape" } or { "swing" }
  local hp = B.hp[act]
  s.role, s.pk, s.pt, s.calls = "king", nil, 0, 0               -- (a puppet's shadow summoned, its time)
  if s.shade then                                  -- the shadow: two puppets' moves more in each act,
    s.moves = act == 1 and { "swing", "leap", "cape", "dash", "summon" }     -- all six in the third,
           or act == 2 and { "swing", "volley", "crown", "pound", "summon" } -- and he summons in each
           or { "swing", "summon" }
  end
  if act == 3 then
    for _, r in ipairs(run.data.saved) do
      if TAKEN[r] then s.moves[#s.moves + 1] = TAKEN[r] hp = hp + B.more end
    end
  end
  s.hp, s.max = hp, hp
  s.cx, s.cl, s.lx, s.lt, s.sx, s.sl = 0, 0, 0, 0, 0, 0     -- the crown, a falling lamp, a snare
  shadows.boss, shadows.beaten = s, false
  -- the soldiers of the first act, made now, waiting in the wings
  s.soldiers = {}
  if act == 1 or s.shade then
    for n = 1, 2 do
      local o = shadows.add(s.x, s.y + s.h, "soldier")
      o.on = false
      s.soldiers[n] = o
    end
  end
end

local function wall_near(s, by)
  return move.blocked(s.face > 0 and s.x + s.w or s.x - by, s.y, by, s.h - 2)
end

local function start(s, m)
  local x, y = s.x + s.w / 2, s.y + s.h
  s.state, s.t, s.landed = m, 0, false
  if m == "summon" then sound.play("summon") end
  if m == "summon" and s.shade and s.pt == 0 then
    -- the shadow calls a puppet's shadow too, each in turn, into the wing
    -- away from Komali
    local w = require("rooms").w
    s.calls = s.calls + 1
    s.pk = PUPPETS[(s.calls - 1) % #PUPPETS + 1]
    local far_left = require("body").k.x > w / 2
    s.px, s.pf, s.pt, s.pc, s.pgot = far_left and 32 or w - 32, far_left and 1 or -1, B.puppet.life, 0, false
    fx.tear(s.px, y - 20, 0)
  end
  if m == "summon" then                            -- in from the wings, either side
    local w = require("rooms").w
    for n, o in ipairs(s.soldiers) do
      if not o.on then
        o.on, o.hp, o.state, o.t, o.vx = true, shadows.S.hp, "walk", 0, 0
        o.x, o.y = n == 1 and 24 or w - 34, y - o.h
        fx.tear(o.x + 5, o.y + 10, 0)
      end
    end
  elseif m == "crown" then
    s.cx, s.cy, s.cv, s.cl = x + s.face * 10, s.y + 6, s.face * B.crown.speed, B.crown.out * 2
  elseif m == "leap" then
    s.vx, s.vy = s.face * B.leap.across, -B.leap.up
  elseif m == "pound" then
    s.wl, s.wr, s.wt, s.hitl, s.hitr = x, x, B.pound.life, false, false
    sound.play("pound")
  elseif m == "snare" then
    s.sx, s.sl = s.tx, B.snare.life
  elseif m == "ring" then
    s.ring = 8
  elseif m == "dash" and wall_near(s, 48) then
    s.face = -s.face
  end
end

function kind.update(s, body, k, dx)
  local st, kx = s.state, k.x + k.w / 2
  local cx, feet = s.x + s.w / 2, s.y + s.h
  if st == "walk" then
    s.face = dx < 0 and -1 or 1
    local dist = math.abs(dx)
    local go = dist > B.far and s.face or 0
    s.vx = (go ~= 0 and not wall_near(s, 2)) and go * B.speed or 0
    s.think = s.think - 1
    if s.think <= 0 or (dist < B.near and s.think < 30) then
      s.turn = s.turn + 1
      local m = dist < B.near and "swing" or s.moves[(s.turn - 1) % #s.moves + 1]
      if m == "summon" and s.soldiers[1].on and s.soldiers[2].on and (not s.shade or s.pt > 0) then m = "swing" end
      s.move, s.state, s.vx, s.tx = m, "wind", 0, kx
      s.t = B.wind[m] * (s.shown[m] and 1 or 2)
      s.shown[m] = true
    end
  elseif st == "wind" then
    s.vx = 0
    if s.move ~= "dash" then s.face = dx < 0 and -1 or 1 end
    s.t = s.t - 1
    if s.t <= 0 then start(s, s.move) end
  elseif st == "swing" then
    s.t = s.t + 1
    local S_ = B.swing
    if s.t > 4 and s.t < 12 and not s.landed and shadows.overlap(s.face > 0 and s.x + s.w or s.x - S_.w, s.y + 6, S_.w, S_.h, k)
       and body.hurt(S_.n, cx) then
      s.landed = true
      shadows.hits = shadows.hits + 1
    end
    if s.t >= 20 then s.state, s.t = "rest", B.rest end
  elseif st == "cape" then
    s.t = s.t + 1
    if s.t >= B.cape.frames then s.state, s.t = "rest", B.rest // 2 end
  elseif st == "leap" then
    s.t = s.t + 1
    if s.t > 4 and s.vy >= 0 and move.blocked(s.x, feet, s.w, 1) then
      s.vx = 0
      if not s.landed and math.abs(kx - cx) < 30 and math.abs(k.y + k.h - feet) < 30 and body.hurt(B.leap.n, cx) then
        shadows.hits = shadows.hits + 1
      end
      fx.spark(cx + s.face * 16, feet - 4)
      s.state, s.t = "rest", B.rest
    end
  elseif st == "volley" then
    s.t = s.t + 1
    local V = B.volley
    if s.t % V.gap == 1 and fight.shots then
      local ex, ey = kx - (cx + s.face * 12), k.y + k.h / 2 - (s.y + 10)
      local len = math.max(1, math.sqrt(ex * ex + ey * ey))
      fight.shots.fire(cx + s.face * 12, s.y + 10, ex / len * V.speed, ey / len * V.speed, V.life, V.n, false)
    end
    if s.t >= V.gap * V.count then s.state, s.t = "rest", B.rest end
  elseif st == "dash" then
    s.t = s.t + 1
    if wall_near(s, 2) or s.t > B.dash.most then
      s.state, s.t, s.vx = "rest", B.rest, 0
    else
      s.vx = s.face * B.dash.speed
      if not s.landed and shadows.overlap(s.x, s.y, s.w, s.h, k) and body.hurt(B.dash.n, cx) then
        s.landed = true
        shadows.hits = shadows.hits + 1
      end
    end
  elseif st == "pound" or st == "crown" or st == "snare" or st == "summon" then
    s.t = s.t + 1
    if s.t >= 16 then s.state, s.t = "rest", B.rest end
  elseif st == "ring" then
    s.t = s.t + 1
    s.ring = 8 + (B.ring.r - 8) * s.t / B.ring.frames
    local d = math.sqrt((kx - cx) ^ 2 + (k.y + k.h / 2 - (s.y + s.h / 2)) ^ 2)
    if not s.landed and math.abs(d - s.ring) < 6 and body.hurt(B.ring.n, cx) then
      s.landed = true
      shadows.hits = shadows.hits + 1
    end
    if s.t >= B.ring.frames then s.state, s.t, s.ring = "rest", B.rest, 0 end
  elseif st == "rest" or st == "reel" then
    s.vx = s.vx * 0.85
    s.t = s.t - 1
    if s.t <= 0 then s.state, s.think = "walk", 30 end
  end
  -- the crown: out, and back to his hand
  if s.cl > 0 then
    s.cl = s.cl - 1
    if s.cl == B.crown.out then s.cv = -s.cv end
    s.cx = s.cx + s.cv
    if s.cx >= k.x and s.cx < k.x + k.w and s.cy >= k.y and s.cy < k.y + k.h and body.hurt(B.crown.n, s.cx - s.cv) then
      shadows.hits = shadows.hits + 1
    end
  end
  -- a puppet's shadow, summoned: it waits a moment in the wing, then does
  -- its puppet's move once, and tears away
  if s.pt > 0 then
    s.pt = s.pt - 1
    local P, D = B.puppet, SHADE[s.pk]
    local age = P.life - s.pt
    if age > P.wait then
      if D.dash then
        s.px = s.px + s.pf * D.dash
        if not s.pgot and math.abs(kx - s.px) < 12 + D.w * 2 and math.abs(k.y + k.h - feet) < 30 and body.hurt(D.n, s.px) then
          s.pgot = true
          shadows.hits = shadows.hits + 1
        end
        if move.blocked(s.px + s.pf * D.w * 4, feet - 8, 1, 1) then s.pt = 0 end
      elseif (age - P.wait) % P.gap == 1 and s.pc < P.count and fight.shots then
        local hx, hy = s.px + s.pf * 12, feet - 30
        local ex, ey = kx - hx, k.y + k.h / 2 - hy
        local len = math.max(1, math.sqrt(ex * ex + ey * ey))
        fight.shots.fire(hx, hy, ex / len * P.speed, ey / len * P.speed, P.shot_life, D.n, false, false, D.ink)
        s.pc = s.pc + 1
      end
    end
    if s.pt == 0 then fx.tear(s.px, feet - 20, 0) end
  end
  -- the second act: lamps fall, a shadow on the floor first where each lands
  if s.act == 2 then
    s.lamp = s.lamp - 1
    if s.lamp == 0 then s.lx, s.lt = kx, B.lamps.warn end
    if s.lamp <= 0 and s.lt > 0 then
      s.lt = s.lt - 1
      if s.lt == 0 then
        if math.abs(kx - s.lx) < 10 and body.hurt(B.lamps.n, s.lx) then shadows.hits = shadows.hits + 1 end
        fx.spark(s.lx, feet - 2)
        fx.tear(s.lx, feet - 6, 0)
        s.lamp = s.shade and B.shade_lamps or B.lamps.every
      end
    end
  end
  -- the pound's shockwave, along the ground either way
  if s.wt > 0 then
    s.wt = s.wt - 1
    local P = B.pound
    s.wl, s.wr = s.wl - P.speed, s.wr + P.speed
    if move.blocked(s.wl, feet - 4, 1, 2) then s.hitl = true end
    if move.blocked(s.wr, feet - 4, 1, 2) then s.hitr = true end
    local kf = k.y + k.h
    if kf > feet - P.high and kf <= feet + 1 then
      for side = 1, 2 do
        local x, gone = side == 1 and s.wl or s.wr, side == 1 and s.hitl or s.hitr
        if not gone and x > k.x - 2 and x < k.x + k.w + 2 and body.hurt(P.n, x) then shadows.hits = shadows.hits + 1 end
      end
    end
  end
  -- the snare, where Komali stood
  if s.sl > 0 then
    s.sl = s.sl - 1
    if k.held == 0 and math.abs(kx - s.sx) < 8 and math.abs(k.y + k.h - feet) < 3 then
      if body.hurt(B.snare.n, s.sx) then shadows.hits = shadows.hits + 1 end
      k.held, s.sl = B.snare.hold, 0
    end
  end
end

-- The cape, while it is up, turns a blow from the front back on Komali; a
-- heavy blow while he walks or gets ready breaks it off.
function kind.strike(s, n, dir, heavy)
  if s.state == "cape" and dir == -s.face then
    fx.spark(s.x + s.w / 2 + s.face * 8, s.y + 12)
    local body = require("body")
    if body.hurt(B.cape.back, s.x + s.w / 2) then shadows.hits = shadows.hits + 1 end
    return "blocked"
  end
  if heavy and (s.state == "walk" or s.state == "wind") then s.state, s.t, s.vx = "reel", 16, dir * 1.5 end
  return "hit"
end

function kind.torn(s)
  shadows.beaten = true
  fx.tear(s.x + s.w / 2, s.y + 4, 0)
  fx.tear(s.x + s.w / 2, s.y + 16, 0)
  for _, o in ipairs(s.soldiers) do o.on = false end
  s.cl, s.lt, s.wt, s.sl, s.pt = 0, 0, 0, 0, 0
end

function kind.draw(s)
  local st, f = s.state, stat("frame")
  local cx, cy, feet = s.x + s.w / 2, s.y + s.h / 2, s.y + s.h
  local n = GUARD
  if st == "walk" then n = math.abs(s.vx) > 0.1 and WALK + s.step // 6 % 4 * 6 or GUARD
  elseif st == "wind" then n = (s.move == "swing" or s.move == "dash") and SWING or s.move == "cape" and CAPE
                             or s.move == "crown" and THROW or s.move == "pound" and LEAP or RAISE
  elseif st == "swing" or st == "dash" then n = SWING
  elseif st == "cape" then n = CAPE
  elseif st == "crown" or st == "volley" or st == "snare" then n = THROW
  elseif st == "leap" then n = LEAP
  elseif st == "pound" then n = POUND
  elseif st == "summon" or st == "ring" then n = RAISE
  elseif st == "reel" then n = REEL end
  if st == "cape" then circ(cx, cy, 22, f % 4 < 2 and C.red or C.marigold) end
  if st == "wind" and s.t < 8 and s.t % 2 == 0 then pal(C.marigold, C.glow) pal(C.red, C.glow) end
  sheet.load(SHEET)
  spr(n, math.floor(cx) - 24, math.floor(feet) - 63, 6, 8, s.face < 0)
  sheet.load("actors.kolam")
  pal()
  if s.pt > 0 then                                 -- a puppet's shadow, from its own sheet, dark
    local D, age = SHADE[s.pk], B.puppet.life - s.pt
    if age > B.puppet.wait or f % 4 < 2 then
      shadows.dark()
      sheet.load(D.sheet)
      spr(D.frame, math.floor(s.px) - D.w * 4, math.floor(feet) - 63, D.w, 8, s.pf < 0)
      sheet.load("actors.kolam")
      pal()
    end
  end
  if s.cl > 0 then                                 -- the crown, spinning
    local a = f * 0.4
    for p = 0, 4 do pset(s.cx + math.cos(a + p * 1.26) * 4, s.cy + math.sin(a + p * 1.26) * 2, C.lamp) end
    circfill(s.cx, s.cy, 2, C.marigold)
  end
  if s.lt > 0 then                                 -- a lamp's shadow on the floor, growing; then the lamp
    local r = 2 + (B.lamps.warn - s.lt) // 6
    line(s.lx - r, feet - 1, s.lx + r, feet - 1, C.ink)
    local y = feet - 8 - s.lt * 4
    circfill(s.lx, y, 3, C.marigold)
    pset(s.lx, y - 4, C.glow)
  end
  if s.wt > 0 then
    local h = 2 + s.wt // 20
    for side = 1, 2 do
      local wx, gone = side == 1 and s.wl or s.wr, side == 1 and s.hitl or s.hitr
      if not gone then line(wx, feet - 1, wx, feet - h * 2, C.marigold) end
    end
  end
  if s.sl > 0 then
    rectfill(s.sx - 6, feet - 2, 13, 2, C.ink)
    line(s.sx - 4, feet - 3, s.sx + 4, feet - 3, C.navy)
  end
  if st == "ring" then
    circ(cx, cy, s.ring, C.vermil)
    circ(cx, cy, s.ring - 1, C.lamp)
  end
end

shadows.kinds.king = kind

return boss
