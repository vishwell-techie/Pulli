-- inventory.lua — what the player is carrying.
--
--   local inventory = require("inventory")
--   local bag = inventory.new(8)        -- room for 8 different kinds of thing
--
--   bag:add("potion", 2)                -- true; false if there was no room
--   bag:remove("potion")                -- true; false if there were none
--   bag:count("potion")                 -- 1
--   bag:has("key")                      -- false
--
--   for i = 1, bag:kinds() do           -- in the order things were picked up
--     local name, count = bag:item(i)
--     print(name .. " x" .. count, 8, 8 + i * 10, 7)
--   end
--
--   bag:save("bag")                     -- into the game's save data
--   bag:load("bag")                     -- false if nothing was saved
--
-- inventory.new(slots, stack)   A bag holding up to `slots` kinds of thing
--     (default 16) and up to `stack` of each kind (default 99).
-- bag:add(name, n)      Add n (default 1). All or nothing: if they do not
--                       all fit, nothing is added and it returns false.
-- bag:remove(name, n)   Take n (default 1). All or nothing, as add.
-- bag:count(name)       How many of this, 0 if none.
-- bag:has(name, n)      True if there are at least n (default 1).
-- bag:kinds()           How many different kinds are held.
-- bag:item(i)           The i-th kind held: its name and count.
-- bag:clear()           Empty the bag.
-- bag:save(key), bag:load(key)   Keep the bag in the save store under keys
--     starting with `key`. The game's manifest must set save_target, and a
--     name must not contain "=".
--
-- This file is part of the Pulli SDK. Copy it into your game and change it
-- as you like.

local inventory = {}
local Bag = {}
Bag.__index = Bag

function inventory.new(slots, stack)
  local bag = setmetatable({}, Bag)
  bag.slots, bag.stack = slots or 16, stack or 99
  bag.names = {}                -- kinds held, in the order first picked up
  bag.counts = {}               -- name -> how many
  return bag
end

function Bag:count(name)
  return self.counts[name] or 0
end

function Bag:has(name, n)
  return self:count(name) >= (n or 1)
end

function Bag:kinds()
  return #self.names
end

function Bag:item(i)
  local name = self.names[i]
  if name then return name, self.counts[name] end
end

function Bag:add(name, n)
  n = n or 1
  local held = self.counts[name]
  if n < 1 or (held or 0) + n > self.stack then return false end
  if not held then
    if #self.names >= self.slots then return false end
    self.names[#self.names + 1] = name
  end
  self.counts[name] = (held or 0) + n
  return true
end

function Bag:remove(name, n)
  n = n or 1
  local held = self.counts[name] or 0
  if n < 1 or held < n then return false end
  if held > n then
    self.counts[name] = held - n
    return true
  end
  self.counts[name] = nil                       -- the last one: free its slot
  for i = 1, #self.names do
    if self.names[i] == name then table.remove(self.names, i) break end
  end
  return true
end

function Bag:clear()
  for i = #self.names, 1, -1 do
    self.counts[self.names[i]] = nil
    self.names[i] = nil
  end
end

-- Saved as key.n = how many kinds, then key.1, key.2, ... = "name=count".
function Bag:save(key)
  local ok = save(key .. ".n", #self.names)
  for i = 1, #self.names do
    local name = self.names[i]
    ok = save(key .. "." .. i, name .. "=" .. self.counts[name]) and ok
  end
  return ok
end

function Bag:load(key)
  local kinds = load(key .. ".n")
  if math.type(kinds) ~= "integer" then return false end
  self:clear()
  for i = 1, kinds do
    local entry = load(key .. "." .. i)
    local name, count = string.match(type(entry) == "string" and entry or "", "^(.+)=(%d+)$")
    if name then self:add(name, math.tointeger(count)) end
  end
  return true
end

return inventory
