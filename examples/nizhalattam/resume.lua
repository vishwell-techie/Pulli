-- resume.lua — taking up a run kept at a door (run.keep_at), when the game
-- is switched on again: main.lua reads it only then, and lets it go once
-- the player has chosen. It asks over the Courtyard: A takes the run up
-- where it was kept, B lets it go.
--
--   resume.update(input, body)   once a frame: true once the choice is made
--   resume.draw(say_at)          the question, and how far the run had got

local run   = require("run")
local fight = require("fight")
local rooms = require("rooms")
local lines = require("lines")
local text  = require("text")
local C     = require("colours")

local resume = {}

-- everything the run carried, back as it was
local function take_up(body)
  local kp, copy = run.data.kept, run.copy
  run.begin(body)
  run.seed, run.typed, run.order, run.half, run.torn = kp.seed, kp.typed, copy(kp.order), kp.half, kp.torn
  run.cleared, run.time = kp.cleared, kp.time
  for n, c in ipairs(kp.charms) do run.charms[n] = c end
  for _, s in ipairs(kp.sharp) do run.sharp[s] = true end
  for _, r in ipairs(kp.lent) do run.lent[r] = true end
  fight.wear(kp.roles)
  fight.worn = math.min(kp.worn, #fight.carried)
  fight.mai, body.k.health = kp.mai, kp.health
  rooms.enter(kp.room, kp.from, body)
end

function resume.update(i, body)
  if i.jump then take_up(body) return true end
  if i.attack then run.drop() return true end
  return false
end

function resume.draw(say_at)
  local kp = run.kept()
  rectfill(6, 60, 308, 120, C.deep)
  rect(6, 60, 308, 120, C.marigold)
  rect(8, 62, 304, 116, C.wood)
  font("small")
  local y = say_at(table.concat(text.wrap(lines.t("kept_q"), 36), "\n"), 76, C.lamp)
  local t = kp.time // 60
  say_at(table.concat(text.wrap(lines.t("summary", string.format("%05d", kp.seed),
         string.format("%d:%02d", t // 60, t % 60), kp.cleared, #kp.order), 34), "\n"), y + 10, C.cloth)
  text.center(lines.t("kept_keys", buttons.a, buttons.b), 150, C.tan)
end

return resume
