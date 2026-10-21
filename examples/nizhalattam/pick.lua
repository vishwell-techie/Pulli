-- pick.lua — choosing roles: at the Aasaan's box (which saved puppets'
-- roles to carry from the start of each run), at the halfway tear (change
-- the roles carried, once a run), and when a puppet lends a role and both
-- places are full (which to give up for it). rooms.lua keeps it in the
-- rooms that need it; at the tear it is the thing to press up at.
--
--   pick.open("box") / pick.open("tear") / pick.open("lend", name)
--   pick.update(input, body)   once a frame while open; false once closed
--   pick.draw()
--
-- Up and down choose. Choosing roles, A marks or unmarks one (two at
-- most), and Done keeps them; B leaves without changing anything. Lent a
-- role, A gives up the role chosen for it, or keeps those carried.

local lines = require("lines")
local fight = require("fight")
local run   = require("run")
local text  = require("text")
local C     = require("colours")

local pick = { open_ = false }
local how, lent, at, note, note_t = nil, nil, 1, nil, 0
local names, marked = {}, {}            -- the rows; the roles marked
local MOST = 2

local function clear(t) for n = #t, 1, -1 do t[n] = nil end end
local function has(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
local function key(role) for name, r in pairs(fight.ROLES) do if r == role then return name end end end
-- a role's name shown, without reading its file: "veeran" is Veeran
local function title(r) return lines.role(r:sub(1, 1):upper() .. r:sub(2)) end

function pick.is_open() return pick.open_ end
function pick.open(kind, name) -- (the tear's shop: open with no kind)
  how, lent, at, note_t = kind or "tear", name, 1, 0
  clear(names) clear(marked)
  local carried = {}
  for n = 2, #fight.carried do carried[#carried + 1] = key(fight.carried[n]) end
  if how == "lend" then
    for _, r in ipairs(carried) do names[#names + 1] = r end
  else
    if how == "tear" then                       -- what he carries, and the saved
      for _, r in ipairs(carried) do names[#names + 1] = r marked[#marked + 1] = r end
    else
      for _, r in ipairs(run.data.chosen) do if run.saved(r) then marked[#marked + 1] = r end end
    end
    for _, r in ipairs(run.data.saved) do if not has(names, r) then names[#names + 1] = r end end
    if how == "tear" and run.torn then note, note_t = "swapped", 9999 end
  end
  pick.open_ = true
end

local function done()
  if how == "box" then
    clear(run.data.chosen)
    for n, r in ipairs(marked) do run.data.chosen[n] = r end
    run.keep()
  elseif how == "tear" then
    local wear = { "komali" }
    for _, r in ipairs(marked) do wear[#wear + 1] = r end
    fight.wear(wear)
    run.torn = true
  end
  pick.open_ = false
end

function pick.update(i, body)
  if not pick.open_ then return false end
  if note_t > 0 and note_t < 9999 then note_t = note_t - 1 end
  local rows = #names + 1                       -- and Done (or Keep my roles)
  if i.door then at = (at - 2) % rows + 1 end   -- up
  if i.down_p then at = at % rows + 1 end
  if i.attack then pick.open_ = false return true end   -- B: as it was
  if i.jump then                                         -- A
    if how == "tear" and run.torn then pick.open_ = false
    elseif at == rows then
      if how == "lend" then pick.open_ = false else done() end
    elseif how == "lend" then
      fight.give_up(names[at], lent)
      pick.open_ = false
    else
      local r = names[at]
      if has(marked, r) then
        for n, m in ipairs(marked) do if m == r then table.remove(marked, n) break end end
      elseif #marked < MOST then marked[#marked + 1] = r
      else note, note_t = "two_most", 90 end
    end
  end
  return true
end

function pick.draw()
  if not pick.open_ then return end
  font("small")
  rectfill(40, 40, 240, 160, C.deep)
  rect(40, 40, 240, 160, C.marigold)
  rect(42, 42, 236, 156, C.wood)
  local head = how == "lend" and lines.t("pick_lend", title(lent))
               or lines.t(how == "box" and "pick_box" or "pick_tear")
  local y = 48
  for _, l in ipairs(text.wrap(head, 30)) do print(l, 52, y, C.lamp) y = y + 14 end
  y = y + 8
  for n = 1, #names + 1 do
    local label = n > #names and lines.t(how == "lend" and "keep_roles" or "done_pick")
                  or title(names[n])
    if n == at then rectfill(46, y - 2, 228, 16, C.wood) print(">", 50, y, C.lamp) end
    if n <= #names and how ~= "lend" then circfill(214, y + 5, 3, has(marked, names[n]) and C.marigold or C.ink) end
    print(label, 62, y, n == at and C.lamp or C.cloth)
    y = y + 18
  end
  if #names == 0 and how ~= "lend" then print(lines.t("none_saved"), 62, y, C.tan) end
  if note_t > 0 then
    y = 170
    for _, l in ipairs(text.wrap(lines.t(note), 30)) do print(l, 52, y, C.vermil) y = y + 15 end
  end
  font()
end

return pick
