-- ch1.lua — chapter 1, Vayal: the paddy fields, 128x128 tiles, the biggest
-- map the console holds. The piece is across the river by the old well; the
-- bridge is held by slimes until its two lamps are lit. The potter has lost
-- three pots in the fields, and gives a clay lamp for them.

local progress = require("progress")

local region = { map = "vayal.ooru", music = 2, pieces = { 1 },   -- fields music
  lines = { villager = "c1_farmer", villager2 = "c1_vill", hint = "c1_start", done = "c1_done", exit = "c1_exit" } }

function region.start(w)
  for _, n in ipairs(w.npcs) do
    if n.who == "villager" then n.say = "farmer" end
  end
  w.card()
  w.tip("c1_start")
end

function region.update(w, dt)
  if w.near(w.p, w.marks.event[1], 48) then w.tip("c1_bridge") end
end

function region.talk(w, n)
  local d = progress.data
  if n.who ~= "potter" then w.say(n.say, region.lines[n.who])
  elseif d.lamp then w.say("potter", "c1_potter4")
  elseif d.pots >= 3 then
    d.lamp = true
    progress.sfx(25)   -- heart
    w.say("potter", "c1_potter3")
    w.say("minmini", "got_lamp")
    progress.save()
  else
    w.say("potter", d.pots > 0 and "c1_potter2" or "c1_potter1", d.pots)
  end
end

return region
