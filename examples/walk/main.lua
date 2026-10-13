-- Walk: a sprite sheet and a map made in Tiled.
--
--   sprites.png   the pictures, 8x8 each. spr(8) draws the ninth one.
--   map.tmx       the map, drawn in Tiled with sprites.png as its tileset.
--                 "ground" is layer 0 and "things" is layer 1. Walls, water
--                 and trees have the property "solid" ticked in Tiled.
--
-- Pick up every gem before the time runs out. Slimes wander the field and
-- come after you when you are near; each touch costs one of three hearts.
-- Gems and slimes are both placed in Tiled, on the "things" layer.

local W, H = 320, 240
local SPEED = 60                -- pixels a second
local SLIME_SPEED = 34
local SIGHT = 56                -- how close a slime notices the player, in pixels
local TIME_LIMIT = 120          -- seconds
local HEARTS = 3
local SAFE_TIME = 1.5           -- seconds a hit leaves the player untouchable

-- Numbers of the pictures on the sheet.
local GEM, PLAYER, SLIME, HEART, NO_HEART = 6, 8, 10, 12, 13
local SOLID = 1                 -- the flag Tiled's "solid" sets

local state                     -- "play", "won" or "lost"
local x, y, flip, steps         -- the player: top-left corner in map pixels
local hearts, safe, time_left
local found, total = 0, 0
local slimes = {}               -- made once in init() and reused
local map_w, map_h              -- the map's size in pixels
local cam_x, cam_y = 0, 0
local found_text, time_text, result
local shown_seconds

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- Is the map solid at this pixel?
local function solid(px, py)
  local tile = map.get(0, px // 8, py // 8)
  return map.flags(tile) & SOLID ~= 0
end

-- Would a body, a 6x6 box inside its sprite, hit something here?
local function blocked(nx, ny)
  return solid(nx + 1, ny + 2) or solid(nx + 6, ny + 2)
      or solid(nx + 1, ny + 7) or solid(nx + 6, ny + 7)
end

-- Move a body one axis at a time, so it slides along a wall. Returns the new
-- place and whether anything stopped it.
local function move(bx, by, dx, dy)
  local hit = false
  if dx ~= 0 then
    if blocked(bx + dx, by) then hit = true else bx = bx + dx end
  end
  if dy ~= 0 then
    if blocked(bx, by + dy) then hit = true else by = by + dy end
  end
  return bx, by, hit
end

-- Start, or start again. Loading the map puts back the gems that were taken.
local function start()
  map.load()
  local tiles_w, tiles_h = map.size()
  map_w, map_h = tiles_w * 8, tiles_h * 8
  total = 0
  local n = 0
  for cy = 0, tiles_h - 1 do
    for cx = 0, tiles_w - 1 do
      local tile = map.get(1, cx, cy)
      if tile == GEM then
        total = total + 1
      elseif tile == SLIME then
        -- A slime drawn in Tiled marks where one starts. Take the tile off
        -- the map and make a slime that can move.
        map.set(1, cx, cy, 0)
        n = n + 1
        local s = slimes[n] or {}
        s.x, s.y, s.dx, s.dy, s.think = cx * 8, cy * 8, 0, 0, 0
        slimes[n] = s
      end
    end
  end
  for i = n + 1, #slimes do slimes[i] = nil end

  x, y, flip, steps = 48, 48, false, 0
  hearts, safe, time_left, found = HEARTS, 0, TIME_LIMIT, 0
  found_text = "GEMS 0/" .. total
  shown_seconds = nil
  state = "play"
end

function init()
  start()
end

local function move_player(dt)
  local dx, dy = 0, 0
  if btn("left")  then dx = -1; flip = true end
  if btn("right") then dx = 1; flip = false end
  if btn("up")    then dy = -1 end
  if btn("down")  then dy = 1 end
  x, y = move(x, y, dx * SPEED * dt, dy * SPEED * dt)
  if dx ~= 0 or dy ~= 0 then steps = steps + dt end

  -- Standing on a gem? Take it off the map.
  local cx, cy = (x + 4) // 8, (y + 4) // 8
  if map.get(1, cx, cy) == GEM then
    map.set(1, cx, cy, 0)
    found = found + 1
    found_text = "GEMS " .. found .. "/" .. total
    if found == total then state, result = "won", "ALL FOUND!" end
  end
end

-- A slime that can see the player heads for them, along whichever of
-- across and up-down is further. Otherwise it wanders: it keeps going one
-- way, and chooses again when it meets a wall or has gone long enough.
local function move_slime(s, dt)
  local to_x, to_y = x - s.x, y - s.y
  if math.abs(to_x) < SIGHT and math.abs(to_y) < SIGHT then
    s.dx, s.dy = 0, 0
    if math.abs(to_x) > math.abs(to_y) then
      s.dx = to_x > 0 and 1 or -1
    else
      s.dy = to_y > 0 and 1 or -1
    end
    s.think = 0
  else
    s.think = s.think - dt
    if s.think <= 0 then
      local way = math.random(5)                 -- four directions, or a rest
      s.dx = way == 1 and -1 or way == 2 and 1 or 0
      s.dy = way == 3 and -1 or way == 4 and 1 or 0
      s.think = 0.5 + math.random() * 1.5
    end
  end
  local hit
  s.x, s.y, hit = move(s.x, s.y, s.dx * SLIME_SPEED * dt, s.dy * SLIME_SPEED * dt)
  if hit then s.think = 0 end

  -- Touching the player costs a heart, unless they were hit a moment ago.
  if safe <= 0 and math.abs(to_x) < 6 and math.abs(to_y) < 6 then
    hearts = hearts - 1
    safe = SAFE_TIME
    if hearts == 0 then state, result = "lost", "THE SLIMES GOT YOU" end
  end
end

function update(dt)
  if state ~= "play" then
    if btnp("a") or btnp("start") then start() end
    return
  end

  move_player(dt)
  for i = 1, #slimes do move_slime(slimes[i], dt) end
  if safe > 0 then safe = safe - dt end

  time_left = time_left - dt
  if time_left <= 0 and state == "play" then
    time_left = 0
    state, result = "lost", "OUT OF TIME"
  end
  -- Build the clock's text once a second, not sixty times.
  local seconds = math.ceil(time_left)
  if seconds ~= shown_seconds then
    shown_seconds = seconds
    time_text = string.format("TIME %d:%02d", seconds // 60, seconds % 60)
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
  local frame = math.floor(time() * 4) % 2
  for i = 1, #slimes do
    spr(SLIME + frame, slimes[i].x, slimes[i].y)
  end
  -- Just after a hit the player blinks.
  if safe <= 0 or math.floor(safe * 10) % 2 == 0 then
    spr(PLAYER + math.floor(steps * 8) % 2, x, y, 1, 1, flip)
  end

  camera()                      -- back to the screen for the top bar
  rectfill(0, 0, W, 11, 32)
  for i = 1, HEARTS do
    spr(i <= hearts and HEART or NO_HEART, 4 + (i - 1) * 9, 2)
  end
  print(found_text, 40, 2, 7)
  print(time_text, 244, 2, time_left <= 10 and 8 or 7)

  if state ~= "play" then
    rectfill(60, 96, 200, 44, 32)
    rect(60, 96, 200, 44, state == "won" and 10 or 8)
    print(result, 160 - #result * 4, 106, state == "won" and 10 or 8)
    print("PRESS A TO PLAY AGAIN", 76, 124, 7)
  end
end
