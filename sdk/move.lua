-- move.lua — move a box through the map without passing through walls.
--
--   local move = require("move")
--   local player = { x = 40, y = 40, w = 6, h = 6 }   -- a box, in map pixels
--
--   function update(dt)
--     local hit_x, hit_y = move.by(player, dx * 60 * dt, dy * 60 * dt)
--     if hit_y and dy > 0 then on_ground = true end
--   end
--
-- A tile is solid when map.flags() of its number has the bit in move.solid
-- set; in Tiled, tick "solid" on the tile. Layer 0 is the one checked.
--
-- move.by(box, dx, dy)   Move the box by dx across, then dy down, as far as
--     it can go towards each. It slides along a wall rather than sticking,
--     and stops flush against it. Returns whether it was stopped across and
--     whether it was stopped up or down. `box` needs x, y, w and h.
-- move.blocked(x, y, w, h)   True if any solid tile lies under that box.
-- move.overlap(a, b)    True if two boxes overlap: for touching enemies.
--
-- Settings:
--   move.solid   the flag bits that make a tile solid (1)
--   move.layer   the map layer to check (0)
--   move.edges   true if the map's edges are walls (true)
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local move = { solid = 1, layer = 0, edges = true }

local function wall(cx, cy)
  local w, h = map.size()
  if cx < 0 or cy < 0 or cx >= w or cy >= h then return move.edges and w > 0 end
  return map.flags(map.get(move.layer, cx, cy)) & move.solid ~= 0
end

function move.blocked(x, y, w, h)
  local x0, y0 = math.floor(x) // 8, math.floor(y) // 8
  local x1, y1 = math.floor(x + w - 1) // 8, math.floor(y + h - 1) // 8
  for cy = y0, y1 do
    for cx = x0, x1 do
      if wall(cx, cy) then return true end
    end
  end
  return false
end

-- Move along one axis in steps of at most a pixel near walls, so that a
-- fast box cannot jump through a wall and a stopped one ends flush with it.
local function slide(box, d, across)
  if d == 0 then return false end
  local step = d > 0 and 1 or -1
  local left = math.abs(d)
  while left > 0 do
    local part = math.min(1, left) * step
    local nx, ny = box.x, box.y
    if across then nx = nx + part else ny = ny + part end
    if move.blocked(nx, ny, box.w, box.h) then return true end
    box.x, box.y = nx, ny
    left = left - 1
  end
  return false
end

function move.by(box, dx, dy)
  local hit_x = slide(box, dx, true)
  local hit_y = slide(box, dy, false)
  return hit_x, hit_y
end

function move.overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return move
