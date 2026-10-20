-- stall.lua — the stall in a story, where mai is spent.
--
--   stall.open()                 up at the stall
--   stall.update(input, body)    once a frame while it is open; false once left
--   stall.draw(body)
--
-- Up and down choose, A buys, B leaves. What is bought lasts the run:
-- mending, a sharper edge for the role worn (its blows 20% stronger), and
-- charms, at most two carried.

local lines = require("lines")
local fight = require("fight")
local run   = require("run")

local stall = { open_ = false }

local ITEMS = {
  { key = "mend", price = 40 },
  { key = "sharpen", price = 80 },
  { key = "bell", price = 90, charm = true },
  { key = "spool", price = 60, charm = true },
  { key = "leave" },
}
stall.ITEMS = ITEMS
local CHARMS = 2

local pick, note, note_t = 1, nil, 0

function stall.open() stall.open_, pick, note, note_t = true, 1, nil, 0 end
function stall.is_open() return stall.open_ end

local function say(key) note, note_t = key, 90 end

local function buy(item, body)
  local k, role = body.k, fight.role()
  if item.key == "leave" then stall.open_ = false return end
  if (item.key == "mend" and k.health >= 100) or (item.key == "sharpen" and run.sharp[role.name])
     or (item.charm and run.charm(item.key)) then say("have") return end
  if item.charm and #run.charms >= CHARMS then say("full") return end
  if fight.mai < item.price then say("no_mai") return end
  fight.mai = fight.mai - item.price
  if item.key == "mend" then k.health = math.min(100, k.health + 25)
  elseif item.key == "sharpen" then run.sharp[role.name] = true
  else run.charms[#run.charms + 1] = item.key end
end

function stall.update(i, body)
  if not stall.open_ then return false end
  if note_t > 0 then note_t = note_t - 1 end
  if i.door then pick = (pick - 2) % #ITEMS + 1 end        -- up
  if i.down_p then pick = pick % #ITEMS + 1 end            -- down
  if i.jump then buy(ITEMS[pick], body) end                -- A
  if i.attack then stall.open_ = false end                 -- B
  return true
end

local function label(item)
  if item.key == "sharpen" then return lines.t("sharpen", lines.role(fight.role().name)) end
  return lines.t(item.key)
end

function stall.draw(body)
  if not stall.open_ then return end
  font("small")
  rectfill(40, 40, 240, 160, 0)
  rect(40, 40, 240, 160, 9)
  print(lines.t("stall"), 52, 48, 10)
  print(lines.t("mai") .. " " .. fight.mai, 200, 48, 12)
  local y = 70
  for n, item in ipairs(ITEMS) do
    local c = n == pick and 10 or 6
    if n == pick then print(">", 50, y, 10) end
    print(label(item), 62, y, c)
    if item.price then print(item.price, 236, y, fight.mai >= item.price and 7 or 5) end
    y = y + 18
  end
  local it = ITEMS[pick]
  if note_t > 0 then print(lines.t(note), 52, 176, 8)
  elseif it.charm then print(lines.t(it.key .. "_d"), 52, 176, 6) end
  font()
end

return stall
