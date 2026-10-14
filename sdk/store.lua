-- store.lua — keep a table in the save data.
--
--   local store = require("store")
--
--   store.save("settings", { volume = 3, name = "Vish", hard = true, keys = { 1, 4, 9 } })
--   local settings = store.load("settings") or { volume = 5 }
--
-- save() keeps only numbers, text and true/false. This packs a whole table,
-- tables inside it included, into one piece of text and keeps that.
--
-- The engine's own save() now keeps tables too, nested four deep, and is
-- simpler. This helper remains for tables nested deeper than that, and for
-- data already saved with it.
--
-- store.save(key, t)   Keep table t under `key`. Returns save()'s answer.
--     Keys and values may be numbers, text or true/false, and values may
--     also be tables; anything else is an error. A table may not contain
--     itself.
-- store.load(key)      The table kept under `key`, or nil if there is none
--     or what is there is not a stored table.
-- store.pack(t), store.unpack(s)   The packing alone, without saving.
--
-- Numbers keep their exact value. The game's manifest must set save_target,
-- and its save_size must leave room: a value may be up to 65535 bytes.
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local store = {}

local MAGIC = "PT1"

local function pack_value(v, out, seen)
  local kind = type(v)
  if kind == "number" then
    if math.type(v) == "integer" then out[#out + 1] = string.pack("<c1i4", "i", v)
    else out[#out + 1] = string.pack("<c1f", "f", v) end
  elseif kind == "string" then
    out[#out + 1] = string.pack("<c1s2", "s", v)
  elseif kind == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif kind == "table" then
    if seen[v] then error("store: a table contains itself", 0) end
    seen[v] = true
    out[#out + 1] = "{"
    for k, item in pairs(v) do
      local kk = type(k)
      if kk ~= "number" and kk ~= "string" and kk ~= "boolean" then
        error("store: a key of type " .. kk .. " cannot be kept", 0)
      end
      pack_value(k, out, seen)
      pack_value(item, out, seen)
    end
    out[#out + 1] = "}"
    seen[v] = nil
  else
    error("store: a value of type " .. kind .. " cannot be kept", 0)
  end
end

function store.pack(t)
  if type(t) ~= "table" then error("store.pack: give a table", 2) end
  local out = { MAGIC }
  local ok, why = pcall(pack_value, t, out, {})
  if not ok then error(why, 2) end
  return table.concat(out)
end

-- Read one value at position i; returns it and where the next one starts.
local function unpack_value(s, i)
  local tag = s:sub(i, i)
  if tag == "i" then return string.unpack("<i4", s, i + 1) end
  if tag == "f" then return string.unpack("<f", s, i + 1) end
  if tag == "s" then return string.unpack("<s2", s, i + 1) end
  if tag == "T" then return true, i + 1 end
  if tag == "F" then return false, i + 1 end
  if tag == "{" then
    local t = {}
    i = i + 1
    while s:sub(i, i) ~= "}" do
      local k, v
      k, i = unpack_value(s, i)
      v, i = unpack_value(s, i)
      if k == nil then error("bad") end
      t[k] = v
    end
    return t, i + 1
  end
  error("bad")
end

function store.unpack(s)
  if type(s) ~= "string" or s:sub(1, #MAGIC) ~= MAGIC then return nil end
  local ok, t, at = pcall(unpack_value, s, #MAGIC + 1)
  if ok and type(t) == "table" and at == #s + 1 then return t end
  return nil
end

function store.save(key, t)
  return save(key, store.pack(t))
end

function store.load(key)
  return store.unpack(load(key))
end

return store
