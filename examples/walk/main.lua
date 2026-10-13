-- Walk: sprites, maps made in Tiled, sound and music.
--
--   sprites.png    the pictures, 8x8 each. spr(8) draws the ninth one.
--   level1.tmx...  the levels, drawn in Tiled with sprites.png as their
--                  tileset. "ground" is layer 0 and "things" is layer 1.
--                  Walls, water and trees have "solid" ticked in Tiled.
--   sfx/, music/   .wav files, numbered in order of name: sfx(0) is the
--                  first file in sfx/.
--
-- Pick up every gem before the time runs out. Slimes wander the field and
-- come after you when you are near; each touch costs one of three hearts.
-- START pauses.
--
-- The player's start is placed in Tiled, on the "things" layer. So are gems
-- and slimes, but only to say how many: each time a level is loaded they are
-- scattered afresh over the ground the player can reach. To add a level,
-- draw one and add a line to LEVELS.

local W, H = 320, 240
local SPEED = 60                -- pixels a second
local SLIME_SPEED = 34
local SIGHT = 56                -- how close a slime notices the player, in pixels
local HEARTS = 3
local SAFE_TIME = 1.5           -- seconds a hit leaves the player untouchable

-- Numbers of the pictures on the sheet.
local GEM, PLAYER, SLIME, HEART, NO_HEART = 6, 8, 10, 12, 13
local SOLID = 1                 -- the flag Tiled's "solid" sets
local SFX_GEM, SFX_HURT, SFX_DONE, SFX_LOST, SFX_PAUSE, SFX_RESUME = 0, 1, 2, 3, 4, 5

-- Each level's map and how many seconds the player gets.
local LEVELS = {
  { map = "level1.ooru", time = 45 },     -- no slimes: room to learn
  { map = "level2.ooru", time = 120 },
  { map = "level3.ooru", time = 170 },
}

local GEM_GAP, SLIME_GAP = 3, 14          -- how far, in tiles, from the player's start

local state                     -- "title", "play", "done" (level finished), "won" or "lost"
local paused = false
local level = 1
local x, y, flip, steps         -- the player: top-left corner in map pixels
local hearts, safe, time_left
local found, total = 0, 0
local slimes = {}               -- made once and reused
local stack = {}                -- reused by mark_reachable()
local map_w, map_h              -- the map's size in pixels
local cam_x, cam_y = 0, 0
local found_text, time_text, level_text, result, prompt
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

-- Scattering needs to know which tiles the player can walk to, or a gem
-- could land behind a wall. The answer is kept in the map itself: a tile of
-- the things layer is marked by its "upside down" flag, which this game
-- never uses for drawing. That needs no table the size of the map.
local function marked(cx, cy)
  local _, _, mark = map.get(1, cx, cy)
  return mark
end

local function set_mark(cx, cy, mark)
  local tile, flip_x = map.get(1, cx, cy)
  map.set(1, cx, cy, tile, flip_x, mark)
end

-- Mark the tile at (cx, cy) and every tile that can be walked to from it.
local function mark_reachable(cx, cy, tiles_w, tiles_h)
  local n = 1
  stack[1] = cy * tiles_w + cx
  set_mark(cx, cy, true)
  while n > 0 do
    local at = stack[n]
    n = n - 1
    local ax, ay = at % tiles_w, at // tiles_w
    for side = 1, 4 do
      local bx = ax + (side == 1 and 1 or side == 2 and -1 or 0)
      local by = ay + (side == 3 and 1 or side == 4 and -1 or 0)
      if bx >= 0 and by >= 0 and bx < tiles_w and by < tiles_h
         and map.flags(map.get(0, bx, by)) & SOLID == 0 and not marked(bx, by) then
        set_mark(bx, by, true)
        n = n + 1
        stack[n] = by * tiles_w + bx
      end
    end
  end
end

-- A random empty tile the player can reach, at least `gap` tiles from where
-- they start. Gives nothing if it cannot find one.
local function random_spot(tiles_w, tiles_h, from_x, from_y, gap)
  for try = 1, 2000 do
    local cx, cy = math.random(0, tiles_w - 1), math.random(0, tiles_h - 1)
    local tile, _, reachable = map.get(1, cx, cy)
    if reachable and tile == 0 and math.abs(cx - from_x) + math.abs(cy - from_y) >= gap then
      return cx, cy
    end
  end
end

-- Start a level, or start it again. Loading the map puts back what was
-- there; then the gems and slimes are scattered, differently every time.
-- Hearts are kept from one level to the next.
local function start(n, full_hearts)
  level = n
  map.load(LEVELS[level].map)
  local tiles_w, tiles_h = map.size()
  map_w, map_h = tiles_w * 8, tiles_h * 8

  -- Count what was drawn in Tiled, and take it off the map.
  local gems, slime_count, start_x, start_y = 0, 0, 1, 1
  for cy = 0, tiles_h - 1 do
    for cx = 0, tiles_w - 1 do
      local tile = map.get(1, cx, cy)
      if tile == GEM then gems = gems + 1
      elseif tile == SLIME then slime_count = slime_count + 1
      elseif tile == PLAYER then start_x, start_y = cx, cy end
      if tile == GEM or tile == SLIME or tile == PLAYER then map.set(1, cx, cy, 0) end
    end
  end
  x, y = start_x * 8, start_y * 8

  mark_reachable(start_x, start_y, tiles_w, tiles_h)
  total = 0
  for i = 1, gems do
    local cx, cy = random_spot(tiles_w, tiles_h, start_x, start_y, GEM_GAP)
    if cx then
      map.set(1, cx, cy, GEM, false, true)      -- still marked, so no second gem lands here
      total = total + 1
    end
  end
  local made = 0
  for i = 1, slime_count do
    local cx, cy = random_spot(tiles_w, tiles_h, start_x, start_y, SLIME_GAP)
    if cx then
      made = made + 1
      local s = slimes[made] or {}
      s.x, s.y, s.dx, s.dy, s.think = cx * 8, cy * 8, 0, 0, 0
      slimes[made] = s
    end
  end
  for i = made + 1, #slimes do slimes[i] = nil end
  for cy = 0, tiles_h - 1 do                    -- rub the marks out again
    for cx = 0, tiles_w - 1 do
      if marked(cx, cy) then set_mark(cx, cy, false) end
    end
  end

  flip, steps, paused = false, 0, false
  if full_hearts then hearts = HEARTS end
  safe, time_left, found = 0, LEVELS[level].time, 0
  found_text = "GEMS 0/" .. total
  level_text = "LEVEL " .. level
  shown_seconds = nil
  state = "play"
  music(0, 400)                 -- fades in; it loops by itself until stopped
end

-- The level is over one way or another: stop the music and say so.
local function finish(new_state, text, what_next, sound)
  state, result, prompt = new_state, text, what_next
  music_stop(300)
  sfx(sound)
end

function init()
  state = "title"
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
    sfx(SFX_GEM)
    if found < total then
      -- carry on
    elseif level < #LEVELS then
      finish("done", "LEVEL " .. level .. " CLEAR", "PRESS A FOR THE NEXT", SFX_DONE)
    else
      finish("won", "YOU FOUND THEM ALL!", "PRESS A TO PLAY AGAIN", SFX_DONE)
    end
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
    if hearts == 0 then
      finish("lost", "THE SLIMES GOT YOU", "PRESS A TO TRY AGAIN", SFX_LOST)
    else
      sfx(SFX_HURT)
    end
  end
end

function update(dt)
  if state ~= "play" then
    if btnp("a") or btnp("start") then
      if state == "title" then
        -- The runtime starts every game with the same random numbers. How
        -- long the player took to press the button makes each game differ.
        math.randomseed(stat("frame"))
        start(1, true)
      elseif state == "done" then start(level + 1, false) -- on to the next level
      elseif state == "won" then start(1, true)           -- from the beginning
      else start(level, true) end                         -- this level again
    end
    return
  end

  if btnp("start") then
    paused = not paused
    sfx(paused and SFX_PAUSE or SFX_RESUME)
  end
  if paused then return end

  move_player(dt)
  for i = 1, #slimes do
    if state == "play" then move_slime(slimes[i], dt) end
  end
  if safe > 0 then safe = safe - dt end

  if state == "play" then
    time_left = time_left - dt
    if time_left <= 0 then
      time_left = 0
      finish("lost", "OUT OF TIME", "PRESS A TO TRY AGAIN", SFX_LOST)
    end
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
  if state == "title" then
    camera()
    for i = 0, 4 do spr(GEM, 120 + i * 18, 70) end
    print("W A L K", 132, 96, 10)
    print("FIND THE GEMS. MIND THE SLIMES.", 36, 122, 7)
    print("PRESS A TO START", 96, 150, 6)
    return
  end
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
  print(level_text, 40, 2, 10)
  print(found_text, 112, 2, 7)
  print(time_text, 244, 2, time_left <= 10 and 8 or 7)

  if paused then
    rectfill(100, 104, 120, 30, 32)
    rect(100, 104, 120, 30, 7)
    print("PAUSED", 136, 110, 7)
    print("PRESS START", 116, 122, 6)
  elseif state ~= "play" then
    local colour = state == "lost" and 8 or 10
    rectfill(60, 96, 200, 44, 32)
    rect(60, 96, 200, 44, colour)
    print(result, 160 - #result * 4, 106, colour)
    print(prompt, 160 - #prompt * 4, 124, 7)
  end
end
