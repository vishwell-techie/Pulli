-- Walk: a sprite sheet and a map made in Tiled.
--
--   sprites.png   the pictures, 8x8 each. spr(8) draws the ninth one.
--   map.tmx       the map, drawn in Tiled with sprites.png as its tileset.
--                 "ground" is layer 0 and "things" is layer 1. Walls, water
--                 and trees have the property "solid" ticked in Tiled.
--
-- Walk with the direction buttons and pick up the gems.

local W, H = 320, 240
local SPEED = 60                -- pixels a second
local GEM = 6                   -- the gem's number on the sheet
local SOLID = 1                 -- the flag Tiled's "solid" sets

local x, y = 48, 48             -- the player's top-left corner, in map pixels
local flip = false              -- facing left?
local steps = 0
local found, total = 0, 0
local map_w, map_h              -- the map's size in pixels
local cam_x, cam_y = 0, 0
local found_text

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- Is the map solid at this pixel?
local function solid(px, py)
  local tile = map.get(0, px // 8, py // 8)
  return map.flags(tile) & SOLID ~= 0
end

-- Would the player's body, a 6x6 box inside the sprite, hit something here?
local function blocked(nx, ny)
  return solid(nx + 1, ny + 2) or solid(nx + 6, ny + 2)
      or solid(nx + 1, ny + 7) or solid(nx + 6, ny + 7)
end

function init()
  local tiles_w, tiles_h = map.size()
  map_w, map_h = tiles_w * 8, tiles_h * 8
  for cy = 0, tiles_h - 1 do
    for cx = 0, tiles_w - 1 do
      if map.get(1, cx, cy) == GEM then total = total + 1 end
    end
  end
  found_text = "GEMS 0 OF " .. total
end

function update(dt)
  local dx, dy = 0, 0
  if btn("left")  then dx = -1; flip = true end
  if btn("right") then dx = 1; flip = false end
  if btn("up")    then dy = -1 end
  if btn("down")  then dy = 1 end

  -- One direction at a time, so the player slides along a wall.
  local nx = x + dx * SPEED * dt
  if not blocked(nx, y) then x = nx end
  local ny = y + dy * SPEED * dt
  if not blocked(x, ny) then y = ny end
  if dx ~= 0 or dy ~= 0 then steps = steps + dt end

  -- Standing on a gem? Take it off the map.
  local cx, cy = (x + 4) // 8, (y + 4) // 8
  if map.get(1, cx, cy) == GEM then
    map.set(1, cx, cy, 0)
    found = found + 1
    found_text = "GEMS " .. found .. " OF " .. total
  end

  -- Keep the player in the middle, and the camera inside the map.
  cam_x = clamp(x + 4 - W / 2, 0, map_w - W)
  cam_y = clamp(y + 4 - H / 2, 0, map_h - H)
end

function draw()
  cls(0)
  camera(cam_x, cam_y)          -- everything below scrolls with the camera
  map.draw(0)
  map.draw(1)
  spr(8 + math.floor(steps * 8) % 2, x, y, 1, 1, flip)   -- two pictures, swapped as it walks

  camera()                      -- back to the screen for the score
  rectfill(0, 0, W, 11, 32)
  print(found_text, 4, 2, 7)
  if found == total then print("ALL FOUND!", 236, 2, 10) end
end
