-- box.lua — the Aasaan's box in the Courtyard, where oil buys repairs that
-- last: more health, the double jump, more mai to start each run with;
-- where the saved puppets' roles to carry are chosen (pick.lua, read only
-- then); and where
-- a seed can be typed, to play that run again (it keeps nothing).
--
--   box.open()                   up at the box
--   box.update(input, body)      once a frame while it is open; false once left
--   box.draw(body)
--
-- Up and down choose, A buys, B leaves. What is bought is kept in the save
-- (run.data.repairs) and takes hold from the next run (run.begin). Typing
-- a seed: left and right move between its five digits, up and down change
-- one, A sets it for the next run, Y goes back to a new seed each run, B
-- leaves it as it was.

local lines = require("lines")
local run   = require("run")
local rooms = require("rooms")
local text  = require("text")
local C     = require("colours")

local box = { open_ = false }

-- each repair: its key, the oil each step costs, and how many steps
local ITEMS = {
  { key = "r_health", prices = { 10, 20, 40 } },
  { key = "r_double", prices = { 25 } },
  { key = "r_mai", prices = { 10, 20, 30 } },
  { key = "r_roles" },
  { key = "r_seed" },
  { key = "leave" },
}
box.ITEMS = ITEMS

local at, note, note_t = 1, nil, 0
local seeding, digits, cur = false, { 0, 0, 0, 0, 0 }, 1

function box.open() box.open_, at, note, note_t, seeding = true, 1, nil, 0, false end
function box.is_open() return box.open_ end

local function steps(item) return run.data.repairs[item.key] or 0 end

local function buy(item)
  if item.key == "leave" then box.open_ = false return end
  if item.key == "r_roles" then box.open_ = false rooms.want("pick").open("box") return end   -- (main.lua runs it)
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
  if note_t > 0 then note_t = note_t - 1 end
  if i.door then at = (at - 2) % #ITEMS + 1 end            -- up
  if i.down_p then at = at % #ITEMS + 1 end                -- down
  if i.jump then buy(ITEMS[at]) end                        -- A
  if i.attack then box.open_ = false end                   -- B
  return true
end

function box.draw(body)
  if not box.open_ then return end
  font("small")
  rectfill(40, 40, 240, 160, C.deep)
  rect(40, 40, 240, 160, C.marigold)
  rect(42, 42, 236, 156, C.wood)
  if seeding then
    print(lines.t("r_seed"), 52, 48, C.lamp)
    font()
    for n = 1, 5 do
      print(digits[n], 116 + n * 16, 96, n == cur and C.lamp or C.cloth)
      if n == cur then rectfill(114 + n * 16, 112, 10, 2, C.lamp) end
    end
    font("small")
    print(lines.t("seed_help", buttons.left, buttons.right, buttons.up, buttons.down), 52, 140, C.tan)
    print(lines.t("seed_help2", buttons.a, buttons.y, buttons.b), 52, 156, C.tan)
    local y = 170
    for _, l in ipairs(text.wrap(lines.t("seeded"), 30)) do print(l, 52, y, C.vermil) y = y + 15 end
    font()
    return
  end
  print(lines.t("box"), 52, 48, C.lamp)
  spr(791, 196, 49)
  print(run.data.oil, 208, 48, C.cloth)
  local y = 66
  for n, item in ipairs(ITEMS) do
    if n == at then rectfill(46, y - 2, 228, 16, C.wood) print(">", 50, y, C.lamp) end
    print(lines.t(item.key), 62, y, n == at and C.lamp or C.cloth)
    if item.prices then
      local done = steps(item)
      for s = 1, #item.prices do circfill(200 + s * 7, y + 6, 2, s <= done and C.marigold or C.wood) end
      if done < #item.prices then print(item.prices[done + 1], 236, y, run.data.oil >= item.prices[done + 1] and C.glow or C.tan) end
    elseif item.key == "r_seed" then
      print(run.next_seed and string.format("%05d", run.next_seed) or lines.t("seed_new"), 176, y, C.tan)
    end
    y = y + 18
  end
  if note_t > 0 then
    y = 170
    for _, l in ipairs(text.wrap(lines.t(note), 30)) do print(l, 52, y, note == "no_oil" and C.vermil or C.lamp) y = y + 15 end
  end
  font()
end

return box
