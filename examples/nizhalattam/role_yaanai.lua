-- role_yaanai.lua — the elephant's role, as Komali wears it (fight.lua
-- reads it when he first carries it). B, slow, wide sweeps of the trunk,
-- the third a heavy slam; in the air a spin; X, the charge: he runs on,
-- carrying the shadows he meets before him, and they are struck hard
-- against the wall that stops him (less hard if nothing does); coming in,
-- a ground pound all round. No blow throws him back. Blows as in fight.lua:
-- frames before (s), landing (a), after (r); cost (n); the box struck (w x h).

local shadows = require("shadows")
local fight   = require("fight")
local move    = require("move")
local C       = require("colours")

local CHARGE = { frames = 30, speed = 3.2, wall = 20, open = 10 }
local carried = {}                             -- the shadows carried by the charge (made once)

local elephant = {
  name = "Yaanai",
  colours = { C.red, C.silver + 32, C.vermil, C.silver, C.red + 32, C.ink,     -- a slate-grey tunic,
              C.saffron, C.red, C.saffron + 32, C.red + 32 },                  -- red breeches
  frames = 0,                                      -- his own frames,
  moves = 768,                                     -- and the elephant's blows (body.FRAME 14-19)
  poses = { "sweep1", "sweep2", "pound", air = "t_air", swap = "stomp", skill = "charge" },
  combo = { { s = 6, a = 5, r = 12, n = 12, w = 26, h = 20 },
            { s = 6, a = 5, r = 12, n = 12, w = 26, h = 20 },
            { s = 9, a = 5, r = 16, n = 20, w = 22, h = 24, heavy = true } },
  air = { s = 3, a = 8, r = 6, n = 10, w = 14, h = 22, around = true },
  swap = { s = 2, a = 6, r = 10, n = 14, w = 30, h = 14, around = true, heavy = true },
  skill = "charge", wait = 360,
  slow = 0.3, dodge_wait = 1.2, guard = 0,
  steady = true,                                   -- no blow throws him back
  CHARGE = CHARGE,
}

function elephant.start_skill(k)
  for n = #carried, 1, -1 do carried[n] = nil end
  return CHARGE.frames
end

-- each frame of the charge: on he goes, the shadows before him with him;
-- a wall, or the charge's end, and they are struck
local function finish(role, wall, face)
  for _, s in ipairs(carried) do
    if s.on then shadows.strike(s, fight.cost(wall and CHARGE.wall or CHARGE.open, role), face, true) end
  end
  fight.hit(true)
end

function elephant.tick_skill(t, role, k)
  local hx = move.by(k, k.face * CHARGE.speed, 0)
  for _, s in ipairs(shadows.list) do
    if s.on and not s.prop and s.hit ~= fight.swing
       and shadows.overlap(k.x + (k.face > 0 and k.w or -6), k.y, 6, k.h, s) then
      s.hit = fight.swing
      if s == shadows.boss then
        shadows.strike(s, fight.cost(8, role), k.face, true)        -- too big to carry
      else
        carried[#carried + 1] = s
      end
    end
  end
  for _, s in ipairs(carried) do                   -- carried before him
    if s.on then
      local x = k.face > 0 and k.x + k.w or k.x - s.w
      if not move.blocked(x, s.y, s.w, s.h - 1) then s.x = x end
      s.vx, s.state, s.t = 0, "reel", 20
    end
  end
  if hx then finish(role, true, k.face) return false end
  if t == 0 then finish(role, false, k.face) end
end

-- dust thrown up behind him as he charges
function elephant.draw_skill(k)
  local f = stat("frame")
  for d = 0, 2 do pset(k.x + k.w / 2 - k.face * (10 + d * 4), k.y + k.h - 1 - (f + d) % 3, C.tan) end
end

return elephant
