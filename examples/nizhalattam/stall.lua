-- stall.lua — the stall in a story, where mai is spent.
--
--   stall.open()                 up at the stall
--   stall.update(input, body)    once a frame while it is open; false once left
--   stall.draw(body)
--
-- A card each (shelf.lua): left and right (or up and down) choose, A buys,
-- B leaves. What is bought lasts the run:
-- mending (30 mai: 25 health, more with the Aasaan's repair), a sharper edge for the role
-- worn (its blows 20% stronger), and charms, at most two carried (three with
-- the repair). Each stall stocks two of the five charms, three with the
-- repair, chosen by the run's seed and the story: the same run, the same
-- stalls.

local lines = require("lines")
local fight = require("fight")
local run   = require("run")
local shelf = require("shelf")
local I     = require("icons")
local C     = require("colours")
local sound = require("sound")

local stall = { open_ = false }

local GOODS = {
  { key = "mend", price = 30, icon = I.mend },
  { key = "sharpen", price = 80, icon = I.sharpen },
}
local CHARMS = {
  { key = "bell", price = 90, charm = true, icon = I.bell },
  { key = "spool", price = 60, charm = true, icon = I.spool },
  { key = "torn", price = 70, charm = true, icon = I.torn },
  { key = "soot", price = 100, charm = true, icon = I.soot },
  { key = "drum", price = 80, charm = true, icon = I.drum },
}
local ITEMS = {}                       -- what this stall has: the goods, and the charms it stocks
stall.ITEMS, stall.CHARMS = ITEMS, CHARMS

-- the charms a stall stocks: from the run's seed and the story's name
local function stock()
  for n = #ITEMS, 1, -1 do ITEMS[n] = nil end
  for n, g in ipairs(GOODS) do ITEMS[n] = g end
  local h = run.seed or 0
  for c in (require("rooms").def().story or ""):gmatch(".") do h = (h * 31 + c:byte()) % 65521 end
  local count = 2 + math.min(1, run.data.repairs.r_stock or 0)
  for n = 0, count - 1 do ITEMS[#ITEMS + 1] = CHARMS[(h + n * 2) % #CHARMS + 1] end
end
local function places() return 2 + math.min(1, run.data.repairs.r_charm3 or 0) end

local pick, note, note_t = 1, nil, 0

function stall.open()
  stall.open_, pick, note, note_t = true, 1, nil, 0
  stock()
end
function stall.is_open() return stall.open_ end

local function say(key) note, note_t = key, 90 sound.play("no") end

local function buy(item, body)
  local k, role = body.k, fight.role()
  if (item.key == "mend" and k.health >= k.max) or (item.key == "sharpen" and run.sharp[role.name])
     or (item.charm and run.charm(item.key)) then say("have") return end
  if item.charm and #run.charms >= places() then say("full") return end
  if fight.mai < item.price then say("no_mai") return end
  fight.mai = fight.mai - item.price
  sound.play("buy")
  if item.key == "mend" then k.health = math.min(k.max, k.health + 25 + 10 * (run.data.repairs.r_mend or 0))
  elseif item.key == "sharpen" then run.sharp[role.name] = true
  else run.charms[#run.charms + 1] = item.key end
end

function stall.update(i, body)
  if not stall.open_ then return false end
  if note_t > 0 then note_t = note_t - 1 end
  pick = shelf.near(i, pick, #ITEMS)
  if i.jump then buy(ITEMS[pick], body) end                -- A
  if i.attack then stall.open_ = false end                 -- B
  return true
end

local function label(item)
  if item.key == "sharpen" then return lines.t("sharpen", lines.role(fight.role().name)) end
  if item.key == "mend" then return lines.t("mend", 25 + 10 * (run.data.repairs.r_mend or 0)) end
  return lines.t(item.key)
end

function stall.draw(body)
  if not stall.open_ then return end
  shelf.panel(lines.t("stall"), fight.mai, 790)
  for n, item in ipairs(ITEMS) do
    local x = 160 - #ITEMS * 20 + (n - 1) * 40
    shelf.card(x, 72, item.icon, n == pick, (item.charm and run.charm(item.key)) or (item.key == "sharpen" and run.sharp[fight.role().name]))
    print(item.price, x + 13 - #tostring(item.price) * 2, 104, fight.mai >= item.price and C.glow or C.tan)
  end
  local it = ITEMS[pick]
  local y = shelf.say(label(it), 124, C.lamp)
  if note_t > 0 then shelf.say(lines.t(note), y + 4, C.vermil)
  elseif it.charm then shelf.say(lines.t(it.key .. "_d"), y + 4, C.tan) end
  font()
end

return stall
