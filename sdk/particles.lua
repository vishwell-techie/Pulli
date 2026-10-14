-- particles.lua — sparks, dust, smoke: many small dots that fly and fade.
--
--   local particles = require("particles")
--   local sparks = particles.new(200)           -- never more than 200 at once
--
--   local BURST = { speed = 70, life = 0.5, gravity = 160, colors = { 10, 9, 8 } }
--   sparks:emit(x, y, 12, BURST)                -- 12 sparks from this point
--
--   function update(dt) sparks:update(dt) end
--   function draw()     sparks:draw()     end   -- with the world, before camera()
--
-- particles.new(most)   A set of particles, at most `most` alive at once
--     (default 100). They are all made here, so emitting makes no garbage.
-- set:emit(x, y, count, style)   Send out `count` particles from (x, y).
--     If the set is full the extra ones are dropped. `style` is a table,
--     best made once and reused, with any of:
--       speed     how fast they leave, in pixels a second (40)
--       jitter    how much the speed varies, 0 to 1 (0.5)
--       angle     which way they go, in degrees: 0 is right, 90 is up (90)
--       spread    how wide a fan around that angle, in degrees (360: all round)
--       life      how many seconds each lasts (0.6)
--       gravity   how fast they are pulled down, pixels a second each second (0)
--       drag      how quickly they slow, 0 for not at all (0)
--       size      how many pixels across (1)
--       colors    the colours a particle goes through as it ages ({ 7 })
-- set:update(dt)   Move them. Call once a frame.
-- set:draw()       Draw them.
-- set:count()      How many are alive.
-- set:clear()      Remove them all.
--
-- This file is part of the Pulli SDK. Copy it into your game and change it
-- as you like.

local particles = {}
local Set = {}
Set.__index = Set

local WHITE = { 7 }

function particles.new(most)
  local set = setmetatable({}, Set)
  set.most = most or 100
  set.alive = 0                 -- set[1..alive] are flying; the rest wait
  for i = 1, set.most do
    set[i] = { x = 0, y = 0, vx = 0, vy = 0, age = 0, life = 1, gravity = 0, drag = 0, size = 1, colors = WHITE }
  end
  return set
end

function Set:emit(x, y, count, style)
  style = style or WHITE        -- any table without the fields gives the defaults
  local speed, jitter = style.speed or 40, style.jitter or 0.5
  local angle, spread = style.angle or 90, style.spread or 360
  for i = 1, count or 1 do
    if self.alive >= self.most then return end
    self.alive = self.alive + 1
    local p = self[self.alive]
    local a = math.rad(angle + (math.random() - 0.5) * spread)
    local v = speed * (1 - jitter * math.random())
    p.x, p.y = x, y
    p.vx, p.vy = math.cos(a) * v, -math.sin(a) * v      -- up the screen is less y
    p.age, p.life = 0, style.life or 0.6
    p.gravity, p.drag = style.gravity or 0, style.drag or 0
    p.size, p.colors = style.size or 1, style.colors or WHITE
  end
end

function Set:update(dt)
  local i = 1
  while i <= self.alive do
    local p = self[i]
    p.age = p.age + dt
    if p.age >= p.life then
      -- Finished: swap it with the last one alive, which is then looked at next.
      self[i], self[self.alive] = self[self.alive], p
      self.alive = self.alive - 1
    else
      p.vy = p.vy + p.gravity * dt
      if p.drag > 0 then
        local keep = math.max(0, 1 - p.drag * dt)
        p.vx, p.vy = p.vx * keep, p.vy * keep
      end
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
      i = i + 1
    end
  end
end

function Set:draw()
  for i = 1, self.alive do
    local p = self[i]
    local colors = p.colors
    local c = colors[math.min(#colors, math.floor(p.age / p.life * #colors) + 1)]
    if p.size <= 1 then
      pset(p.x, p.y, c)
    else
      rectfill(p.x - p.size // 2, p.y - p.size // 2, p.size, p.size, c)
    end
  end
end

function Set:count()
  return self.alive
end

function Set:clear()
  self.alive = 0
end

return particles
