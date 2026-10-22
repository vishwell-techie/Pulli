-- pick.lua — choosing roles: at the Aasaan's box (which saved puppets'
-- roles to carry from the start of each run), at the halfway tear (change
-- the roles carried, once a run), and when a puppet lends a role and both
-- places are full (which to give up for it). rooms.lua reads it where it is
-- wanted; at the tear it is the thing to press up at.
--
--   pick.open("box") / pick.open("tear") / pick.open("lend", name) / pick.open("free")
--   pick.update(input, body)   once a frame while open; false once closed
--   pick.draw()
--
-- Drawn as faces (icons.lua, shelf.lua): along the top Komali and his two
-- places, a padlock on a place not yet bought at the box (run.data.repairs
-- .r_slot); below, every puppet in the order of their stories, in colour if
-- saved, a shadow if not, and a tick for Done. Left and right choose; A
-- puts a puppet in a place or takes it out, and on the tick keeps the
-- choice; B leaves without changing anything. A place bought is for a saved
-- puppet; a role lent in this run needs no place bought. Lent a role with
-- both places full, the faces are the roles carried: A gives one up for it,
-- or on the cross keeps them. The Puppet King beaten, the faces are the
-- puppets not yet saved: A lets that one go (pick.freed), and there is no
-- leaving without choosing.

local lines = require("lines")
local fight = require("fight")
local run   = require("run")
local shelf = require("shelf")
local I     = require("icons")
local C     = require("colours")

local pick = { open_ = false }
local PUPPETS = { "veeran", "vil", "aattakkaari", "yaanai", "mandhiri", "rani" }
pick.PUPPETS = PUPPETS
local how, lent, at, note, note_t = nil, nil, 1, nil, 0
local names, marked = {}, {}            -- the faces to choose from; those in a place

local function clear(t) for n = #t, 1, -1 do t[n] = nil end end
local function has(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
local function key(role) for name, r in pairs(fight.ROLES) do if r == role then return name end end end
-- a role's name shown, without reading its file: "veeran" is Veeran
local function title(r) return lines.role(r:sub(1, 1):upper() .. r:sub(2)) end
local function face(r) return I["f_" .. r] or I.unknown end
local function slots() return run.data.repairs.r_slot or 0 end
-- can this one be carried? saved, or lent in this run (at the tear)
local function free(r) return run.saved(r) or (how == "tear" and run.lent[r]) end
-- places taken by saved puppets that were not lent: at most the places bought
local function bought_used()
  local n = 0
  for _, r in ipairs(marked) do if not (how == "tear" and run.lent[r]) then n = n + 1 end end
  return n
end

function pick.is_open() return pick.open_ end
function pick.open(kind, name) -- (the tear's shop: open with no kind)
  how, lent, at, note_t = kind or "tear", name, 1, 0
  clear(names) clear(marked)
  if how == "lend" then
    for n = 2, #fight.carried do names[#names + 1] = key(fight.carried[n]) end
  elseif how == "free" then
    for _, r in ipairs(PUPPETS) do if not run.saved(r) then names[#names + 1] = r end end
    pick.freed = nil
  else
    for _, r in ipairs(PUPPETS) do names[#names + 1] = r end
    if how == "tear" then
      for n = 2, #fight.carried do marked[#marked + 1] = key(fight.carried[n]) end
      if run.torn then note, note_t = "swapped", 9999 end
    else
      for _, r in ipairs(run.data.chosen) do if run.saved(r) and #marked < slots() then marked[#marked + 1] = r end end
    end
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

local function say(k) note, note_t = k, 90 end

local function choose(r)
  if has(marked, r) then
    for n, m in ipairs(marked) do if m == r then table.remove(marked, n) break end end
  elseif not free(r) then say("not_saved")
  elseif #marked >= 2 then say("two_most")
  elseif not (how == "tear" and run.lent[r]) and bought_used() >= slots() then say("no_slot")
  else marked[#marked + 1] = r end
end

function pick.update(i, body)
  if not pick.open_ then return false end
  if note_t > 0 and note_t < 9999 then note_t = note_t - 1 end
  if how == "free" then                         -- the faces only, and one must be chosen
    at = shelf.near(i, at, #names)
    if i.jump then pick.freed, pick.open_ = names[at], false end
    return true
  end
  at = shelf.near(i, at, #names + 1)            -- the faces, and Done (or Keep)
  if i.attack then pick.open_ = false return true end   -- B: as it was
  if i.jump then                                         -- A
    if how == "tear" and run.torn then pick.open_ = false
    elseif at > #names then
      if how == "lend" then pick.open_ = false else done() end
    elseif how == "lend" then
      fight.give_up(names[at], lent)
      pick.open_ = false
    else choose(names[at]) end
  end
  return true
end

function pick.draw()
  if not pick.open_ then return end
  local head = how == "lend" and lines.t("pick_lend", title(lent)) or how == "free" and lines.t("pick_free")
               or lines.t(how == "box" and "pick_box" or "pick_tear")
  shelf.panel(head)
  -- along the top: Komali, and his places (the one lending, when lending)
  if how == "free" then
    shelf.card(147, 64, I.f_komali, false)
  elseif how == "lend" then
    shelf.card(147, 64, face(lent), true)
  else
    shelf.card(98, 64, I.f_komali, false)
    for n = 1, 2 do
      local x = 98 + n * 36
      local r = marked[n]
      if r then shelf.card(x, 64, face(r), false)
      elseif how == "box" and n > slots() then shelf.card(x, 64, I.lock, false)
      else shelf.card(x, 64, I.slot, false, true) end
    end
  end
  -- below: the faces to choose from, then Done (or Keep)
  local n = how == "free" and #names or #names + 1
  local x0 = 160 - n * 17
  for k = 1, n do
    local x = x0 + (k - 1) * 34
    if k > #names then shelf.card(x, 108, how == "lend" and I.keep or I.done, k == at)
    else
      local r = names[k]
      shelf.card(x, 108, face(r), k == at, how ~= "lend" and how ~= "free" and not free(r))
      if has(marked, r) then circfill(x + 22, 111, 3, C.marigold) circ(x + 22, 111, 3, C.ink) end
    end
  end
  font("small")
  local y, said = 142, nil
  if at > #names then said = lines.t(how == "lend" and "keep_roles" or "done_pick")
  elseif how == "lend" then said = lines.t("give_up", title(names[at]))
  elseif how == "free" then said = title(names[at])
  elseif free(names[at]) then said = title(names[at])
  else said = lines.t("not_saved") end
  y = shelf.say(said, y, C.lamp)
  if note_t > 0 then shelf.say(lines.t(note), y, C.vermil) end
  font()
end

return pick
