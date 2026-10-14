-- quest.lua — keep track of what the player has been asked to do.
--
--   local quest = require("quest")
--
--   quest.define("gems", "The Lost Gems", {
--     "Talk to the elder",
--     { "Find three gems", need = 3 },
--     "Bring them back",
--   })
--
--   quest.start("gems")
--   quest.advance("gems")               -- talked: on to "Find three gems"
--   quest.advance("gems")               -- one gem; two more and it moves on
--   quest.state("gems")                 -- "active"
--   local n, text, have, need = quest.step("gems")   -- 2, "Find three gems", 1, 3
--
-- A quest is "new" until it is started, then "active", then "done" when its
-- last step is finished.
--
-- quest.define(id, title, steps)   Describe a quest. Each step is its text,
--     or a table of its text and `need`, how many times it must be advanced
--     (default 1). Define every quest when the game starts, in init().
-- quest.start(id)        Begin a new quest. False if it was already begun.
-- quest.advance(id, n)   Count n (default 1) towards the current step of an
--     active quest. Returns true if that finished the whole quest.
-- quest.state(id)        "new", "active" or "done".
-- quest.step(id)         The current step of an active quest: its number,
--     its text, how many are counted so far and how many it needs.
-- quest.title(id)        The quest's title.
-- quest.count()  quest.id(i)   How many quests are defined, and the i-th
--     one's id, in the order they were defined: for drawing a quest log.
-- quest.on_change        Set this to a function(id, state) to be told when a
--     quest starts, moves on a step, or is done.
-- quest.save(key)  quest.load(key)   Keep every quest's progress in the save
--     store under keys starting with `key`. The manifest must set
--     save_target. Load after defining; it returns false if nothing was saved.
-- quest.reset()          Put every quest back to "new".
--
-- This file is part of the Pulli SDK. Copy it into your game and change it
-- as you like.

local quest = { on_change = nil }

local quests = {}               -- id -> { title, steps, state, at, have }
local order = {}                -- ids, in the order defined

local function get(id, fn)
  local q = quests[id]
  if not q then error("quest." .. fn .. ": no quest called '" .. tostring(id) .. "'", 3) end
  return q
end

local function tell(id, q)
  if quest.on_change then quest.on_change(id, q.state) end
end

function quest.define(id, title, steps)
  if type(steps) ~= "table" or #steps == 0 then error("quest.define: a quest needs at least one step", 2) end
  local q = { title = title, steps = {}, state = "new", at = 1, have = 0 }
  for i = 1, #steps do
    local s = steps[i]
    if type(s) == "table" then
      q.steps[i] = { text = s[1], need = s.need or 1 }
    else
      q.steps[i] = { text = s, need = 1 }
    end
  end
  if not quests[id] then order[#order + 1] = id end
  quests[id] = q
end

function quest.start(id)
  local q = get(id, "start")
  if q.state ~= "new" then return false end
  q.state, q.at, q.have = "active", 1, 0
  tell(id, q)
  return true
end

function quest.advance(id, n)
  local q = get(id, "advance")
  if q.state ~= "active" then return false end
  q.have = q.have + (n or 1)
  if q.have < q.steps[q.at].need then return false end
  q.have = 0                                  -- this step is finished
  if q.at < #q.steps then
    q.at = q.at + 1
    tell(id, q)
    return false
  end
  q.state = "done"
  tell(id, q)
  return true
end

function quest.state(id)
  return get(id, "state").state
end

function quest.title(id)
  return get(id, "title").title
end

function quest.step(id)
  local q = get(id, "step")
  if q.state ~= "active" then return nil end
  local s = q.steps[q.at]
  return q.at, s.text, q.have, s.need
end

function quest.count()
  return #order
end

function quest.id(i)
  return order[i]
end

function quest.reset()
  for i = 1, #order do
    local q = quests[order[i]]
    q.state, q.at, q.have = "new", 1, 0
  end
end

-- Saved as key.<id> = "state step have", one entry for each quest.
function quest.save(key)
  local ok = true
  for i = 1, #order do
    local q = quests[order[i]]
    ok = save(key .. "." .. order[i], q.state .. " " .. q.at .. " " .. q.have) and ok
  end
  return ok
end

function quest.load(key)
  local found = false
  for i = 1, #order do
    local q = quests[order[i]]
    local entry = load(key .. "." .. order[i])
    local state, at, have = string.match(type(entry) == "string" and entry or "", "^(%a+) (%d+) (%d+)$")
    at, have = math.tointeger(at), math.tointeger(have)
    -- A save from an older version of the game may not fit the quest as it
    -- is now defined; anything that does not fit is left as it was.
    if (state == "new" or state == "active" or state == "done") and at >= 1 and at <= #q.steps
       and have < q.steps[at].need then
      q.state, q.at, q.have = state, at, have
      found = true
    end
  end
  return found
end

return quest
