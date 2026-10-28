-- role_mandhiri.lua — the Minister's role, as Komali wears it (fight.lua
-- reads it when he first carries it). B throws an ink dart, aimed with up
-- or down; a shadow it strikes moves at half speed for a while; X conjures
-- a paper Komali where he stands, which the shadows go for instead of him
-- until it is torn or its time runs out; coming in, he drops an ink snare
-- at his feet, which holds the first shadow that walks into it. His snares
-- last longer than other traps. His frames are on the Minister's sheet.

local shadows = require("shadows")
local fight   = require("fight")
local fx      = require("fx")
local C       = require("colours")

local DECOY = { hp = 30, frames = 600 }
local SNARE = { most = 3, life = 600, hold = 120 }   -- (traps last longer: 600, not 300)
local lure = { x = 0, y = 0, w = 10, h = 20, hp = 0, t = 0, held = 0, vx = 0, vy = 0, face = 1 }
lure.body = { k = lure, hurt = function(n) lure.hp = lure.hp - n return n end }
local nx, ny, nl = {}, {}, {}                        -- the snares lying in wait
for n = 1, SNARE.most do nx[n], ny[n], nl[n] = 0, 0, 0 end

local minister = {
  name = "Mandhiri",
  colours = { C.red, C.cloth, C.vermil, C.glow, C.red + 32, C.warm,          -- a white robe,
              C.saffron, C.navy, C.saffron + 32, C.navy + 32 },              -- dark breeches
  frames = 0,                                      -- his own frames,
  moves = 470, sheet = "mandhiri.kolam",           -- and the Minister's (body.FRAME 14-19), on his sheet
  poses = { "dart", air = "m_air", swap = "m_spin", skill = "conjure" },
  bow = true,                                      -- (his darts fly as arrows do: shots.lua)
  shot = { s = 4, a = 0, r = 10, n = 7, speed = 4, life = 40 },
  swap = { s = 0, a = 6, r = 8, n = 6, w = 12, h = 16, around = true },
  skill = "decoy", wait = 600,
  slow = 0.5, dodge_wait = 1, guard = 0,
  DECOY = DECOY, SNARE = SNARE,
}

-- an ink dart; aim -1 up, 1 down
function minister.loose(k, m, aim)
  local x, y, v = k.x + k.w / 2 + k.face * 6, k.y + 8, m.speed
  fight.shots.fire(x, y, k.face * v * (aim == 0 and 1 or 0.75), aim * v * 0.66, m.life, fight.cost(m.n, minister),
                   true, false, true)
end

-- the decoy: a paper Komali where he stands
function minister.start_skill(k)
  lure.x, lure.y, lure.face, lure.hp, lure.t, lure.held = k.x, k.y, k.face, DECOY.hp, DECOY.frames, 0
  shadows.lure = lure
  fx.tear(k.x + k.w / 2, k.y + 6, 0)
  return 20
end

-- coming in: a snare at his feet (the oldest goes if three lie already)
function minister.on_swap(k)
  local n, old = 1, nl[1]
  for i = 2, SNARE.most do if nl[i] < old then n, old = i, nl[i] end end
  nx[n], ny[n], nl[n] = k.x + k.w / 2, k.y + k.h, SNARE.life
end

-- the snares hold the first shadow that walks into each (not a boss)
function minister.each()
  for n = 1, SNARE.most do
    if nl[n] > 0 then
      nl[n] = nl[n] - 1
      for _, s in ipairs(shadows.list) do
        if s.on and not s.prop and s ~= shadows.boss and s.state ~= "reel"
           and math.abs(s.x + s.w / 2 - nx[n]) < 8 and math.abs(s.y + s.h - ny[n]) < 6 then
          s.state, s.t, s.vx, nl[n] = "reel", SNARE.hold, 0, 0
          fx.spark(nx[n], ny[n] - 4)
          break
        end
      end
    end
  end
end

function minister.draw_each()
  for n = 1, SNARE.most do
    if nl[n] > 0 then
      rectfill(nx[n] - 6, ny[n] - 2, 13, 2, C.ink)
      line(nx[n] - 4, ny[n] - 3, nx[n] + 4, ny[n] - 3, C.navy)
    end
  end
  if shadows.lure == lure then                     -- the paper Komali, flickering as it tears
    if lure.hp > 10 or stat("frame") % 4 < 2 then
      for c = 1, 31 do pal(c, c % 3 == 0 and C.warm or C.cloth) end
      pal(C.ink, C.tan)
      spr(0, math.floor(lure.x) - 7, math.floor(lure.y) - 12, 3, 4, lure.face < 0)
      pal()
    end
  end
end

return minister
