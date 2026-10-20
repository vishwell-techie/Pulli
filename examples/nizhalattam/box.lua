-- box.lua — the Aasaan's box in the Courtyard, where oil buys repairs that
-- last: more health, the double jump, more mai to start each run with.
--
--   box.open()                   up at the box
--   box.update(input, body)      once a frame while it is open; false once left
--   box.draw(body)
--
-- Up and down choose, A buys, B leaves. What is bought is kept in the save
-- (run.data.repairs) and takes hold from the next run (run.begin).

local lines = require("lines")
local run   = require("run")
local C     = require("colours")

local box = { open_ = false }

-- each repair: its key, the oil each step costs, and how many steps
local ITEMS = {
  { key = "r_health", prices = { 10, 20, 40 } },
  { key = "r_double", prices = { 25 } },
  { key = "r_mai", prices = { 10, 20, 30 } },
  { key = "leave" },
}
box.ITEMS = ITEMS

local pick, note, note_t = 1, nil, 0

function box.open() box.open_, pick, note, note_t = true, 1, nil, 0 end
function box.is_open() return box.open_ end

local function steps(item) return run.data.repairs[item.key] or 0 end

local function buy(item)
  if item.key == "leave" then box.open_ = false return end
  local done = steps(item)
  if done >= #item.prices then note, note_t = "done_r", 90 return end
  local price = item.prices[done + 1]
  if run.data.oil < price then note, note_t = "no_oil", 90 return end
  run.data.oil = run.data.oil - price
  run.data.repairs[item.key] = done + 1
  run.keep()
  note, note_t = "bought_r", 90
end

function box.update(i, body)
  if not box.open_ then return false end
  if note_t > 0 then note_t = note_t - 1 end
  if i.door then pick = (pick - 2) % #ITEMS + 1 end        -- up
  if i.down_p then pick = pick % #ITEMS + 1 end            -- down
  if i.jump then buy(ITEMS[pick]) end                      -- A
  if i.attack then box.open_ = false end                   -- B
  return true
end

function box.draw(body)
  if not box.open_ then return end
  font("small")
  rectfill(40, 40, 240, 160, C.deep)
  rect(40, 40, 240, 160, C.marigold)
  rect(42, 42, 236, 156, C.wood)
  print(lines.t("box"), 52, 48, C.lamp)
  spr(791, 196, 49)
  print(run.data.oil, 208, 48, C.cloth)
  local y = 72
  for n, item in ipairs(ITEMS) do
    if n == pick then rectfill(46, y - 2, 228, 18, C.wood) print(">", 50, y, C.lamp) end
    print(lines.t(item.key), 62, y, n == pick and C.lamp or C.cloth)
    if item.prices then
      local done = steps(item)
      for s = 1, #item.prices do circfill(200 + s * 7, y + 6, 2, s <= done and C.marigold or C.wood) end
      if done < #item.prices then print(item.prices[done + 1], 236, y, run.data.oil >= item.prices[done + 1] and C.glow or C.tan) end
    end
    y = y + 22
  end
  if note_t > 0 then print(lines.t(note), 52, 176, note == "bought_r" and C.lamp or C.vermil) end
  font()
end

return box
