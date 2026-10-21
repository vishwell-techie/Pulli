-- role_aattakkaari.lua — the dancer's role, as Komali wears it (fight.lua
-- reads it when he first carries it). B, spinning kicks, each carrying him
-- forward, the third all round; in the air a spinning kick; X, the bells:
-- a dash through the shadows in his way, stunning them, no blow touching
-- him; coming in, a whirl that strikes all round. Each dodge leaves a ring
-- that strikes, as the bell anklet's does. Blows as in fight.lua: frames
-- before (s), landing (a), after (r); cost (n); the box struck (w x h);
-- push moves him on while it lands.

local shadows = require("shadows")
local fight   = require("fight")
local move    = require("move")
local C       = require("colours")

local DASH = { frames = 16, speed = 4, n = 6, stun = 90 }

local dancer = {
  name = "Aattakkaari",
  colours = { C.red, C.navy, C.vermil, C.blue, C.red + 32, C.navy + 32,     -- a dark blue tunic,
              C.saffron, C.vermil, C.saffron + 32, C.vermil + 32 },          -- red breeches
  frames = 0,                                      -- his own frames,
  moves = 500,                                     -- and the dancer's blows (body.FRAME 14-19)
  combo = { { s = 3, a = 4, r = 8, n = 8, w = 16, h = 16, push = 1.6 },
            { s = 3, a = 4, r = 8, n = 8, w = 16, h = 16, push = 1.6 },
            { s = 4, a = 6, r = 12, n = 14, w = 14, h = 22, around = true, push = 1.2 } },
  air = { s = 2, a = 8, r = 4, n = 9, w = 14, h = 22, around = true },
  swap = { s = 0, a = 14, r = 4, n = 10, w = 16, h = 24, around = true, heavy = true },
  skill = "bells", wait = 300,
  slow = 0.6, dodge_wait = 1, guard = 0,
  ring = true,                                     -- each dodge leaves a ring that strikes
  DASH = DASH,
}

-- the bells: a dash ahead; nothing touches him while it lasts
function dancer.start_skill(k)
  k.untouch = DASH.frames
  return DASH.frames
end

-- each shadow he passes is struck and stunned (a boss only struck)
function dancer.tick_skill(t, role, k)
  move.by(k, k.face * DASH.speed, 0)
  for _, s in ipairs(shadows.list) do
    if s.on and not s.prop and s.hit ~= fight.swing and shadows.overlap(k.x, k.y, k.w, k.h, s) then
      s.hit = fight.swing
      local r = shadows.strike(s, fight.cost(DASH.n, role), k.face, false)
      if r == "hit" or r == "blocked" then
        if s ~= shadows.boss then s.state, s.t, s.vx = "reel", DASH.stun, 0 end
        fight.hit(false)
      elseif r == "torn" then
        fight.hit(false)
      end
    end
  end
end

-- the bells ringing behind him as he dashes
function dancer.draw_skill(k)
  local f = stat("frame")
  for b = 0, 2 do pset(k.x + k.w / 2 - k.face * (8 + b * 5), k.y + k.h - 4 - (f + b) % 4, C.lamp) end
end

return dancer
