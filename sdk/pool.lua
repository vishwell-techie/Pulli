-- pool.lua — reuse objects instead of making new ones.
--
--   local pool = require("pool")
--   local bullets = pool.new(64, function() return { x = 0, y = 0, dx = 0 } end)
--
--   local b = bullets:get()               -- nil if all 64 are in use
--   if b then b.x, b.y, b.dx = x, y, 200 end
--
--   for i = bullets.n, 1, -1 do           -- every one in use; backwards, so
--     local b = bullets[i]                -- freeing as you go is safe
--     b.x = b.x + b.dx * dt
--     if b.x > 320 then bullets:free_at(i) end
--   end
--
-- Making a table creates garbage when it is dropped, and on the console the
-- garbage collector costs time. A pool makes all its objects at the start
-- and hands the same ones out again.
--
-- pool.new(size, make)   A pool of `size` objects, each made by calling
--     make() once, now.
-- p:get()          An object not in use, or nil if every one is. It keeps
--                  whatever values it had last time: set every field.
-- p:free(obj)      Give an object back.
-- p:free_at(i)     Give back p[i]. The last one in use moves into its place.
-- p.n              How many are in use: they are p[1] to p[p.n].
-- p:clear()        Give them all back.
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local pool = {}
local Pool = {}
Pool.__index = Pool

function pool.new(size, make)
  if type(make) ~= "function" then error("pool.new: give a function that makes one object", 2) end
  local p = setmetatable({ n = 0, size = size }, Pool)
  for i = 1, size do p[i] = make() end
  return p
end

function Pool:get()
  if self.n >= self.size then return nil end
  self.n = self.n + 1
  return self[self.n]
end

function Pool:free_at(i)
  if i < 1 or i > self.n then return end
  self[i], self[self.n] = self[self.n], self[i]
  self.n = self.n - 1
end

function Pool:free(obj)
  for i = 1, self.n do
    if self[i] == obj then self:free_at(i) return true end
  end
  return false
end

function Pool:clear()
  self.n = 0
end

return pool
