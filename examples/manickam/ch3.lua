-- ch3.lua — chapter 3, Thamarai Kulam: the lotus lake. Two pieces lie on
-- islands reached by sunken stepping stones, which rise when Kayal steps on
-- the old switches; slimes here can swim. Seven lotuses for the festival
-- grow round the lake. The water moves by palette cycling: three of the
-- palette's blues swap colours a few times a second, so every water tile on
-- screen ripples without one tile being redrawn.

local progress = require("progress")

local region = { map = "lake.ooru", music = 4, pieces = { 3, 4 },   -- lake music
  lines = { villager = "c3_fisher1", hint = "c3_start", done = "c3_done", exit = "c3_exit" } }
local WATER = { 12, 44, 28 }            -- the blues that turn
local saved, clock, turn = {}, 0, 0

function region.start(w)
  w.npcs[1].say = "fisher"
  region.lines.villager = "c3_fisher1"
  for i, c in ipairs(WATER) do saved[i] = { palette(c) } end
  w.card()
  w.tip("c3_start")
end

function region.update(w, dt)
  clock = clock + dt
  if clock > 0.25 then
    clock, turn = 0, turn + 1
    for i, c in ipairs(WATER) do
      local rgb = saved[(i + turn) % 3 + 1]
      palette(c, rgb[1], rgb[2], rgb[3])
    end
  end
  for _, s in ipairs(w.slimes) do
    if s.swim and w.near(s, w.p, 40) then w.tip("c3_swim") break end
  end
end

function region.talk(w, n)
  w.say("fisher", region.lines.villager)
  region.lines.villager = "c3_fisher2"
end

function region.event(w, what)
  if what == "switch" then w.tip("c3_switch") end
end

-- Put the blues back, for the title screen and every other region.
function region.leave(w)
  for i, c in ipairs(WATER) do palette(c, saved[i][1], saved[i][2], saved[i][3]) end
end

return region
