-- role_rani.lua — the Queen's role, as Komali wears it (fight.lua reads it
-- when he first carries it). B, lamp-fire: a short flame ahead, the third a
-- wide one; in the air a spin; X, the lamp shield: it turns the next three
-- blows aside (k.ward, body.lua), and while it holds his health slowly
-- mends; coming in, a ring of fire all round. Her frames are on the
-- Queen's sheet. Blows as in fight.lua.

local C = require("colours")

local SHIELD = { blows = 3, frames = 600, mend = 40 }
local held = 0                                    -- frames the shield has held

local queen = {
  name = "Rani",
  colours = { C.red, C.oxblood, C.vermil, C.red, C.red + 32, C.oxblood + 32,      -- a crimson blouse,
              C.saffron, C.marigold, C.saffron + 32, C.marigold + 32 },           -- gold silk
  frames = 0,                                      -- his own frames,
  moves = 470, sheet = "rani.kolam",               -- and the Queen's (body.FRAME 14-19), on her sheet
  poses = { "fire1", "fire2", "fire3", air = "q_air", swap = "ring", skill = "lamp_up" },
  combo = { { s = 4, a = 6, r = 8, n = 9, w = 24, h = 14 },
            { s = 4, a = 6, r = 8, n = 9, w = 24, h = 14 },
            { s = 5, a = 6, r = 12, n = 14, w = 28, h = 20 } },
  air = { s = 2, a = 8, r = 4, n = 9, w = 14, h = 22, around = true },
  swap = { s = 0, a = 10, r = 6, n = 12, w = 30, h = 30, around = true, heavy = true },
  skill = "shield", wait = 720,
  slow = 0.5, dodge_wait = 1, guard = 0,
  fire = true,                                     -- (her blows are drawn as flames)
  SHIELD = SHIELD,
}

function queen.start_skill(k)
  k.ward, held = SHIELD.blows, 0
  require("sound").play("shield")
  return 12
end

-- while the shield holds, he mends; it fades after a while unbroken
function queen.each(k)
  if k.ward > 0 then
    held = held + 1
    if held % SHIELD.mend == 0 and k.health < k.max then k.health = k.health + 1 end
    if held >= SHIELD.frames then k.ward = 0 end
  end
end

function queen.draw_each(k)
  if k.ward > 0 then
    local cx, cy, f = k.x + k.w / 2, k.y + k.h / 2, stat("frame")
    circ(cx, cy, 15, f % 6 < 3 and C.lamp or C.marigold)
    for b = 1, k.ward do pset(cx - 6 + b * 3, k.y - 6, C.lamp) end
  end
end

return queen
