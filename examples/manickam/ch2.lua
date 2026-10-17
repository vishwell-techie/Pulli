-- ch2.lua — chapter 2, Aalamaram Kaadu: the banyan forest at night, a maze
-- of corridors under the trees. Only Minmini's light and the lamps Kayal
-- lights show the way. Shrine gates close the great banyan's clearing, the
-- heart lotus's dead end and the way out; the woodcutter's three keys lie
-- far apart in the maze, so it has to be searched. When she has the piece,
-- two red eyes watch from the dark.

local progress = require("progress")
local script   = require("script")

local region = { map = "forest.ooru", music = 3, dark = true, pieces = { 2 },   -- forest music
  lines = { villager = "c2_wood", hint = "c2_start", done = "c2_done", exit = "c2_exit" } }
local eyes

function region.start(w)
  w.npcs[1].say = "woodcutter"
  eyes = nil
  w.card()
  w.tip("c2_start")
end

function region.event(w, what, t)
  if what == "got" and t.kind == "piece" then       -- inside the piece's cut-scene
    eyes = w.marks.guide[1]
    progress.sfx(21)   -- hiss
    script.wait(1.2)
    script.say("minmini", "c2_eyes1")
    eyes = nil
    script.say("kayal", "c2_eyes2")
  end
end

function region.lights(w)
  if eyes then w.light(eyes.x, eyes.y, 6) end
end

function region.draw_top(w)
  if eyes and stat("frame") % 50 > 4 then spr(950, eyes.x - 4, eyes.y - 4) end
end

return region
