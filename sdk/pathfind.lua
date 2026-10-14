-- pathfind.lua — the shortest way round the walls of the map.
--
--   local pathfind = require("pathfind")
--
--   local path = pathfind.find(slime_cx, slime_cy, player_cx, player_cy)
--   if path then
--     local next_x, next_y = path[1].x, path[1].y     -- the first tile to step to
--   end
--
-- Positions are tiles, not pixels: a pixel position divided by 8, rounded
-- down. Steps go across and up-down, never diagonally.
--
-- pathfind.find(from_x, from_y, to_x, to_y)   A list of the tiles to walk
--     through, each { x = , y = }, ending at the goal and not including the
--     start. An empty list if already there. nil if there is no way, or if
--     finding it would take more than pathfind.limit tiles of searching.
--
-- Settings:
--   pathfind.solid   the map.flags() bits of a tile that cannot be walked (1)
--   pathfind.layer   the map layer to read (0)
--   pathfind.limit   the most tiles to search before giving up (2000). It
--                    keeps a search for an unreachable goal from taking long.
--   pathfind.walkable(x, y)   replace this to decide for yourself which
--                    tiles can be walked, for instance to avoid water.
--
-- Searching takes time. Find a path when the goal moves to a new tile, or
-- every so often, not every frame.
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local pathfind = { solid = 1, layer = 0, limit = 2000 }

function pathfind.walkable(x, y)
  local w, h = map.size()
  if x < 0 or y < 0 or x >= w or y >= h then return false end
  return map.flags(map.get(pathfind.layer, x, y)) & pathfind.solid == 0
end

-- A heap of tile numbers ordered by their estimated total cost, cheapest
-- on top, so the next tile to look at is always to hand.
local function push(heap, cost, id)
  local i = #heap + 1
  heap[i] = id
  while i > 1 do
    local up = i // 2
    if cost[heap[up]] <= cost[heap[i]] then break end
    heap[up], heap[i] = heap[i], heap[up]
    i = up
  end
end

local function pop(heap, cost)
  local top, last = heap[1], #heap
  heap[1] = heap[last]
  heap[last] = nil
  local i = 1
  while true do
    local l, r, small = 2 * i, 2 * i + 1, i
    if l < last and cost[heap[l]] < cost[heap[small]] then small = l end
    if r < last and cost[heap[r]] < cost[heap[small]] then small = r end
    if small == i then break end
    heap[i], heap[small] = heap[small], heap[i]
    i = small
  end
  return top
end

local SIDES = { 1, 0, -1, 0, 0, 1, 0, -1 }

function pathfind.find(from_x, from_y, to_x, to_y)
  if from_x == to_x and from_y == to_y then return {} end
  if not pathfind.walkable(to_x, to_y) then return nil end
  local w = map.size()
  local start, goal = from_y * w + from_x, to_y * w + to_x
  local walked, total, came = { [start] = 0 }, {}, {}
  local function guess(id)         -- steps it would take with no walls in the way
    return math.abs(id % w - to_x) + math.abs(id // w - to_y)
  end
  total[start] = guess(start)
  local heap, searched, done = { start }, 0, {}
  while #heap > 0 do
    local id = pop(heap, total)
    if done[id] then goto continue end      -- an older, dearer entry for a tile already finished
    done[id] = true
    if id == goal then
      local path, n = {}, 0
      while id ~= start do n = n + 1; path[n] = id; id = came[id] end
      for i = 1, n // 2 do path[i], path[n + 1 - i] = path[n + 1 - i], path[i] end
      for i = 1, n do path[i] = { x = path[i] % w, y = path[i] // w } end
      return path
    end
    searched = searched + 1
    if searched > pathfind.limit then return nil end
    local x, y = id % w, id // w
    for s = 1, 7, 2 do
      local nx, ny = x + SIDES[s], y + SIDES[s + 1]
      local next_id = ny * w + nx
      if pathfind.walkable(nx, ny) and (walked[next_id] == nil or walked[id] + 1 < walked[next_id]) then
        walked[next_id] = walked[id] + 1
        total[next_id] = walked[next_id] + guess(next_id)
        came[next_id] = id
        push(heap, total, next_id)
      end
    end
    ::continue::
  end
  return nil
end

return pathfind
