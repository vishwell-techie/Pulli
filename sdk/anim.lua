-- anim.lua — sprite animations by name.
--
--   local anim = require("anim")
--   local hero = anim.new({
--     idle = { frames = { 8 } },
--     walk = { frames = { 8, 9 }, fps = 8 },
--     hurt = { frames = { 12, 13, 12 }, fps = 12, loop = false },
--   })
--
--   function update(dt)
--     hero:play(moving and "walk" or "idle")   -- carries on if already playing
--     hero:update(dt)
--   end
--
--   function draw()
--     hero:draw(x, y, facing_left)            -- or spr(hero:frame(), x, y)
--   end
--
-- anim.new(set)     An animation player for a set of named animations. Each
--     has `frames`, a list of sprite numbers; `fps`, frames a second (8);
--     and `loop`, false to stop on the last frame (true). It starts on the
--     first animation in alphabetical order; call play() to choose.
-- a:play(name, restart)   Switch to an animation. Playing the one already
--     playing changes nothing unless `restart` is true.
-- a:update(dt)      Move the animation on. Call once a frame.
-- a:frame()         The sprite number to draw now.
-- a:done()          True once an animation that does not loop has ended.
-- a:playing()       The name of the animation playing.
-- a:draw(x, y, flip_x, flip_y, w, h)   spr() the current frame.
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local anim = {}
local Player = {}
Player.__index = Player

function anim.new(set)
  local first
  for name, a in pairs(set) do
    if type(a.frames) ~= "table" or #a.frames == 0 then
      error("anim.new: '" .. tostring(name) .. "' has no frames", 2)
    end
    if first == nil or name < first then first = name end
  end
  if first == nil then error("anim.new: no animations given", 2) end
  local p = setmetatable({ set = set }, Player)
  p:play(first, true)
  return p
end

function Player:play(name, restart)
  local a = self.set[name]
  if not a then error("anim: no animation called '" .. tostring(name) .. "'", 2) end
  if name == self.name and not restart then return end
  self.name, self.current, self.time, self.index, self.ended = name, a, 0, 1, false
end

function Player:update(dt)
  local a = self.current
  local spf = 1 / (a.fps or 8)
  self.time = self.time + dt
  while self.time >= spf and not self.ended do
    self.time = self.time - spf
    if self.index < #a.frames then
      self.index = self.index + 1
    elseif a.loop == false then
      self.ended = true
    else
      self.index = 1
    end
  end
end

function Player:frame()
  return self.current.frames[self.index]
end

function Player:done()
  return self.ended
end

function Player:playing()
  return self.name
end

function Player:draw(x, y, flip_x, flip_y, w, h)
  spr(self:frame(), x, y, w or 1, h or 1, flip_x, flip_y)
end

return anim
