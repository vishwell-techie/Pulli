-- box.lua — the Aasaan's box in the Courtyard, where oil buys repairs that
-- last: more health, the double jump, more mai to start each run with, and
-- the places for roles to carry from the start; where those roles are
-- chosen (pick.lua, read only then); where the pages of the King's story
-- found so far are read again (pages.lua, read only then); and where a seed
-- can be typed, to play that run again (it keeps nothing).
--
--   box.open()                   up at the box
--   box.update(input, body)      once a frame while it is open; false once left
--   box.draw(body)
--
-- A card each (shelf.lua): left and right (or up and down) choose, A buys,
-- B leaves. What is bought is kept in the save (run.data.repairs) and takes
-- hold from the next run (run.begin). Typing a seed: left and right move
-- between its five digits, up and down change one, A sets it for the next
-- run, Y goes back to a new seed each run, B leaves it as it was.

local lines = require("lines")
local run   = require("run")
local rooms = require("rooms")
local shelf = require("shelf")
local I     = require("icons")
local C     = require("colours")

local box = { open_ = false }

-- each repair: its key, its icon, the oil each step costs
local ITEMS = {
  { key = "r_health", icon = I.health, prices = { 10, 20, 40 } },
  { key = "r_double", icon = I.double, prices = { 25 } },
  { key = "r_mai", icon = I.mai, prices = { 10, 20, 30 } },
  { key = "r_slot", icon = I.slot, prices = { 20, 45 } },     -- the places for roles chosen
  { key = "r_roles", icon = I.roles },
  { key = "r_pages", icon = I.page },
  { key = "r_seed", icon = I.seed },
}
box.ITEMS = ITEMS

local at, note, note_t = 1, nil, 0
local seeding, digits, cur = false, { 0, 0, 0, 0, 0 }, 1
local reading, page = nil, 1                   -- pages.lua while the pages are read; which one

function box.open() box.open_, at, note, note_t, seeding = true, 1, nil, 0, false end
function box.is_open() return box.open_ end

local function steps(item) return run.data.repairs[item.key] or 0 end

local function buy(item)
  if item.key == "r_roles" then box.open_ = false rooms.want("pick").open("box") return end   -- (main.lua runs it)
  if item.key == "r_pages" then
    if #run.data.pages == 0 then note, note_t = "no_pages", 90 return end
    reading, page = require("pages"), 1
    return
  end
  if item.key == "r_seed" then
    local v = run.next_seed or run.seed or 0
    for n = 5, 1, -1 do digits[n], v = v % 10, v // 10 end
    seeding, cur = true, 1
    return
  end
  local done = steps(item)
  if done >= #item.prices then note, note_t = "done_r", 90 return end
  local price = item.prices[done + 1]
  if run.data.oil < price then note, note_t = "no_oil", 90 return end
  run.data.oil = run.data.oil - price
  run.data.repairs[item.key] = done + 1
  run.keep()
  note, note_t = "bought_r", 90
end

local function seed_update(i)
  if i.left_p then cur = (cur - 2) % 5 + 1 end
  if i.right_p then cur = cur % 5 + 1 end
  if i.door then digits[cur] = (digits[cur] + 1) % 10 end
  if i.down_p then digits[cur] = (digits[cur] - 1) % 10 end
  if i.jump then
    local v = 0
    for n = 1, 5 do v = v * 10 + digits[n] end
    run.next_seed, seeding, note, note_t = v, false, "seeded", 120
  end
  if i.dodge then run.next_seed, seeding = nil, false end
  if i.attack then seeding = false end
end

function box.update(i, body)
  if not box.open_ then return false end
  if seeding then seed_update(i) return true end
  if reading then                                         -- left and right turn the pages; B puts them away
    if i.left_p then page = (page - 2) % #run.data.pages + 1 end
    if i.right_p then page = page % #run.data.pages + 1 end
    if i.attack then reading = nil unrequire("pages") end
    return true
  end
  if note_t > 0 then note_t = note_t - 1 end
  at = shelf.near(i, at, #ITEMS)
  if i.jump then buy(ITEMS[at]) end                        -- A
  if i.attack then box.open_ = false end                   -- B
  return true
end

function box.draw(body)
  if not box.open_ then return end
  if reading then
    shelf.panel(lines.t("page_n", page, reading.COUNT))
    font("small")
    shelf.say(reading.text(page), 72, C.cloth)
    print(buttons.left .. " " .. buttons.right .. "    " .. buttons.b, 48, 176, C.tan)
    font()
    return
  end
  shelf.panel(lines.t(seeding and "r_seed" or "box"), run.data.oil, 791)
  if seeding then
    font()
    for n = 1, 5 do
      print(digits[n], 116 + n * 16, 90, n == cur and C.lamp or C.cloth)
      if n == cur then rectfill(114 + n * 16, 106, 10, 2, C.lamp) end
    end
    font("small")
    print(lines.t("seed_help", buttons.left, buttons.right, buttons.up, buttons.down), 48, 128, C.tan)
    print(lines.t("seed_help2", buttons.a, buttons.y, buttons.b), 48, 144, C.tan)
    shelf.say(lines.t("seeded"), 166, C.vermil)
    font()
    return
  end
  for n, item in ipairs(ITEMS) do
    local x = 46 + (n - 1) * 34
    shelf.card(x, 72, item.icon, n == at)
    if item.prices then
      local done = steps(item)
      shelf.dots(x + 13, 104, done, #item.prices)
      if done < #item.prices then
        print(item.prices[done + 1], x + 13 - #tostring(item.prices[done + 1]) * 2, 110,
              run.data.oil >= item.prices[done + 1] and C.glow or C.tan)
      end
    end
  end
  local item = ITEMS[at]
  local y = shelf.say(lines.t(item.key), 132, C.lamp)
  if item.key == "r_seed" then
    print(run.next_seed and string.format("%05d", run.next_seed) or lines.t("seed_new"), 48, y, C.tan)
  end
  if note_t > 0 then shelf.say(lines.t(note), 166, note == "no_oil" and C.vermil or C.lamp) end
  font()
end

return box
