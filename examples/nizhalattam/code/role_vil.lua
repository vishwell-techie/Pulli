-- role_vil.lua — the archer's role, as Komali wears it (fight.lua reads it
-- when he first carries it). B looses an arrow, aimed with up or down; B
-- held, a piercing arrow; X, a rain of arrows on a spot ahead; coming in, a
-- leap back loosing three arrows down at what is in front. Each arrow that
-- strikes makes the next fly further, until one misses (shots.streak).
--
-- An arrow: frames drawing (s), then loosed, frames after (r); its cost (n),
-- speed and life (frames); heavy ones pierce.

local shots = require("shots")
local fight = require("fight")
local C     = require("colours")

local FURTHER, FURTHEST = 5, 25                               -- frames of flight more a hit in a row
local RAIN = { frames = 40, ahead = 80, every = 4, n = 6 }    -- the rain of arrows
local rain_x, rain_y = 0, 0

local vil = {
  name = "Vil",
  colours = { C.red, C.leaf, C.vermil, C.leaf, C.red + 32, C.leaf + 32, C.oxblood, C.leaf + 32,   -- green tunic,
              C.saffron, C.tan, C.saffron + 32, C.tan + 32,                     -- buff breeches,
              C.marigold, C.leather, C.marigold + 32, C.leather + 32 },         -- a leather cap
  frames = 1536,                                   -- Komali's frames with a bow
  bow = true,
  shot = { s = 5, a = 0, r = 10, n = 7, speed = 5, life = 28 },
  heavy = { s = 2, a = 0, r = 14, n = 16, speed = 6, life = 44, heavy = true },
  swap = { s = 4, a = 0, r = 12, n = 8, speed = 4.5, life = 26, leap = true },
  skill = "rain", wait = 480,
  slow = 0.4, dodge_wait = 1, guard = 0,
  RAIN = RAIN,
}
vil.air = vil.shot

-- an arrow loosed (three down and ahead, leaping back); aim -1 up, 1 down
function vil.loose(k, m, aim)
  local life = m.life + math.min(FURTHEST, shots.streak * FURTHER)
  local x, y, v, n = k.x + k.w / 2 + k.face * 6, k.y + 8, m.speed, fight.cost(m.n, vil)
  if m.leap then
    for a = 1, 3 do shots.fire(x, y + 4, k.face * v * (0.35 + a * 0.2), v * 0.75, life, n, true, false) end
  elseif aim == 0 then
    shots.fire(x, y, k.face * v, 0, life, n, true, m.heavy)
  else
    shots.fire(x, y, k.face * v * 0.75, aim * v * 0.66, life, n, true, m.heavy)
  end
end

-- the rain: a spot ahead, arrows falling on it, spread across it; they pierce
function vil.start_skill(k)
  rain_x, rain_y = k.x + k.w / 2 + k.face * RAIN.ahead, k.y - 100
  return RAIN.frames
end

function vil.tick_skill(t)
  if t % RAIN.every == 0 and t > 4 then
    shots.fire(rain_x + (t * 7 % 5 - 2) * 9, rain_y, 0, 6, 40, fight.cost(RAIN.n, vil), true, true)
  end
end

return vil
