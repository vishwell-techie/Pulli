-- ch0.lua — chapter 0, Kayalur at dusk: the village, and learning how to
-- get by. Light the three street lamps (A), keep the slimes from the pond
-- off with Minmini's flare (B), then leave by the east gate.

local progress = require("progress")

local region = { map = "village.ooru", music = 1,   -- village music
  lines = { paati = "c0_paati1", villager = "c0_vill1", villager2 = "c0_vill2" } }
local STREET_Y = 19                     -- the street lamps are those on or below this row

local function street_lit(w) return w.lit_count(STREET_Y) end

function region.start(w)
  region.lines.paati = "c0_paati1"
  w.card()
  w.tip("c0_start")
  w.tip("c0_lamps")
end

function region.update(w, dt)
  for _, s in ipairs(w.slimes) do
    if w.near(s, w.p, 70) then w.tip("c0_slimes") break end
  end
end

function region.event(w, what)
  if what ~= "lit" then return end
  local lit, all = street_lit(w)
  if lit == all then
    w.tip("c0_all")
    region.lines.paati = "c0_paati2"
  else
    w.tip("c0_lit")
  end
end

function region.exit(w)
  local lit, all = street_lit(w)
  if lit == all then
    w.finish()
  else
    w.p.x = w.p.x - 10
    w.say("minmini", "c0_gate")
  end
end

function region.hint(w)
  local lit, all = street_lit(w)
  return lit == all and "c0_all" or "c0_lamps"
end

return region
