-- level.lua — the gem hunt: the first playable chapter, Kayalur at dusk,
-- until the regions of the full story are built.
--
-- Pick up every gem before the time runs out. Slimes wander the field and
-- come after you when you are near, round walls and through water; each
-- touch costs one of three hearts. You can wade into water too, but it slows
-- you down, and you stay slow for three seconds after you climb out.
-- START pauses, music included.
--
-- The levels are drawn in Tiled with sprites.png as their tileset. The
-- player's start is placed on the "things" layer; so are gems and slimes,
-- but only to say how many: each time a level is loaded they are scattered
-- afresh over dry ground the player can reach.
--
-- Adds the scenes "play", "pause" and "over".

local scene      = require("scene")        -- title, play, pause and the end of a level
local input      = require("input")        -- presses that count once
local move       = require("move")         -- walking without passing through walls
local pathfind   = require("pathfind")     -- slimes find their way round walls
local anim       = require("anim")         -- the player's steps, the slimes' wobble
local follow     = require("camera_follow")
local timer      = require("timer")        -- the moment of safety after a hit
local text       = require("text")
local transition = require("transition")   -- fading from one level to the next
local particles  = require("particles")    -- drips from a wet player
local story      = require("story")
local progress   = require("progress")

local W, H = 320, 240
local SPEED = 60                -- pixels a second
local WATER_SPEED = 30          -- in water, and for a while after
local WET_TIME = 3              -- seconds the player stays slow after leaving water
local SLIME_SPEED = 34
local SIGHT = 56                -- how close a slime notices the player, in pixels
local HEARTS = 3
local SAFE_TIME = 1.5           -- seconds a hit leaves the player untouchable

-- Numbers of the pictures on the sheet (cell x + 64 * cell y): the hunt's
-- 8x8 sprites sit in the strip under the title art.
local GEM, PLAYER, SLIME, HEART, NO_HEART = 1926, 1984, 1986, 1988, 1989
local SOLID, WATER = 1, 2       -- tile flags: Tiled's "solid", and water's flags
local SFX_GEM, SFX_HURT, SFX_DONE, SFX_LOST, SFX_PAUSE, SFX_RESUME = 0, 1, 2, 3, 4, 5

-- Each level's map and how many seconds the player gets.
local LEVELS = {
  { map = "level1.ooru", time = 45 },     -- no slimes: room to learn
  { map = "level2.ooru", time = 120 },
  { map = "level3.ooru", time = 170 },
}

local GEM_GAP, SLIME_GAP = 3, 14          -- how far, in tiles, from the player's start

-- The player is a 6x6 box inside its 8x8 sprite, which is drawn one pixel
-- left of it and two above. Slimes are the same.
local player = { x = 0, y = 0, w = 6, h = 6, flip = false }
local walker = anim.new({
  stand = { frames = { PLAYER } },
  walk  = { frames = { PLAYER, PLAYER + 1 }, fps = 8 },
})
local wobble = anim.new({ wobble = { frames = { SLIME, SLIME + 1 }, fps = 4 } })
local cam = follow.new({ smooth = 0 })    -- 0: keeps the player exactly in the middle
local drops = particles.new(24)
local DRIP = { speed = 20, angle = 270, spread = 60, life = 0.4, gravity = 120, colors = { 12, 44 } }

local level = 1
local playing                   -- false once the level is won or lost
local hearts, hurt, time_left
local wet, wading, dripping     -- seconds left of being slow; in water now; drip timer
local found, total = 0, 0
local slimes = {}               -- made once and reused
local map_w, map_h              -- the map's size in pixels
local found_text, time_text, level_text
local shown_seconds

pathfind.limit = 300            -- a slime only looks a few tiles ahead

local function flags_at(px, py)
  return map.flags(map.get(0, px // 8, py // 8))
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

-- Mark the tile at (cx, cy) and every tile that can be walked or waded to
-- from it. The list of tiles still to look at is made here and dropped at
-- the end: on a big map it is tens of kilobytes, not worth keeping in play.
local function mark_reachable(cx, cy, tiles_w, tiles_h)
  local stack, n = {}, 1
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

-- A random empty tile of dry ground the player can reach, at least `gap`
-- tiles from where they start. Gives nothing if it cannot find one.
local function random_spot(tiles_w, tiles_h, from_x, from_y, gap)
  for try = 1, 2000 do
    local cx, cy = math.random(0, tiles_w - 1), math.random(0, tiles_h - 1)
    local tile, _, reachable = map.get(1, cx, cy)
    if reachable and tile == 0 and math.abs(cx - from_x) + math.abs(cy - from_y) >= gap
       and map.flags(map.get(0, cx, cy)) & WATER == 0 then
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
  player.x, player.y, player.flip = start_x * 8 + 1, start_y * 8 + 2, false

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
      local s = slimes[made] or { w = 6, h = 6 }
      s.x, s.y, s.dx, s.dy, s.think, s.look, s.to_x = cx * 8 + 1, cy * 8 + 2, 0, 0, 0, 0, nil
      slimes[made] = s
    end
  end
  for i = made + 1, #slimes do slimes[i] = nil end
  for cy = 0, tiles_h - 1 do                    -- rub the marks out again
    for cx = 0, tiles_w - 1 do
      if marked(cx, cy) then set_mark(cx, cy, false) end
    end
  end

  if full_hearts then hearts = HEARTS end
  hurt = timer.cooldown(SAFE_TIME)
  dripping = timer.cooldown(0.15)
  time_left, found, wet, wading, playing = LEVELS[level].time, 0, 0, false, true
  drops:clear()
  walker:play("stand")
  found_text = "0/" .. total
  level_text = level .. "/" .. #LEVELS
  shown_seconds = math.ceil(time_left)
  time_text = text.clock(shown_seconds)
  cam:bounds(0, 0, map_w, map_h)
  cam:snap(player.x + 3, player.y + 2)
  progress.music(0, 400)        -- fades in; it loops by itself until stopped
end

-- The level is over one way or another: stop the music and say so.
local function finish(how, message, what_next, sound)
  playing = false
  music_stop(300)
  progress.sfx(sound)
  if how == "won" then                          -- the chapter is done: keep it, now
    progress.data.unlocked = math.max(progress.data.unlocked, 1)
    progress.checkpoint()
  end
  scene.push("over", how, message, what_next)
end

local function move_player(dt)
  local dx, dy = 0, 0
  if btn("left")  then dx = -1; player.flip = true end
  if btn("right") then dx = 1; player.flip = false end
  if btn("up")    then dy = -1 end
  if btn("down")  then dy = 1 end

  -- In water, and for WET_TIME seconds after, the player wades.
  wading = flags_at(player.x + 3, player.y + 3) & WATER ~= 0
  if wading then wet = WET_TIME else wet = math.max(0, wet - dt) end
  local speed = wet > 0 and WATER_SPEED or SPEED
  move.by(player, dx * speed * dt, dy * speed * dt)
  walker:play((dx ~= 0 or dy ~= 0) and "walk" or "stand")
  walker:update(dt)
  if wet > 0 and not wading and dripping:use() then
    drops:emit(player.x + 3, player.y + 4, 1, DRIP)
  end

  -- Standing on a gem? Take it off the map.
  local cx, cy = (player.x + 3) // 8, (player.y + 2) // 8
  if map.get(1, cx, cy) == GEM then
    map.set(1, cx, cy, 0)
    found = found + 1
    found_text = found .. "/" .. total
    progress.sfx(SFX_GEM)
    if found < total then
      -- carry on
    elseif level < #LEVELS then
      finish("next", story.t("clear", level), story.t("next"), SFX_DONE)
    else
      finish("won", story.t("won"), story.t("again"), SFX_DONE)
    end
  end
end

local function sign(v)
  return v > 0.5 and 1 or v < -0.5 and -1 or 0
end

-- A slime that can see the player finds the way to them, round walls and
-- through water, and looks again a few times a second. Otherwise it
-- wanders: it keeps going one way, and chooses again when it meets a wall
-- or has gone long enough.
local function move_slime(s, dt)
  local to_x, to_y = player.x - s.x, player.y - s.y
  if math.abs(to_x) < SIGHT and math.abs(to_y) < SIGHT then
    s.look = s.look - dt
    if s.look <= 0 then
      s.look = 0.25
      local path = pathfind.find((s.x + 3) // 8, (s.y + 3) // 8, (player.x + 3) // 8, (player.y + 3) // 8)
      if path and path[1] then
        s.to_x, s.to_y = path[1].x * 8 + 1, path[1].y * 8 + 2
      else
        s.to_x = nil            -- on the player's tile, or no way there
      end
    end
    if s.to_x then
      s.dx, s.dy = sign(s.to_x - s.x), sign(s.to_y - s.y)
      if s.dx == 0 and s.dy == 0 then s.look = 0 end          -- arrived: look again
    else
      s.dx, s.dy = sign(to_x), sign(to_y)
    end
    s.think = 0
  else
    s.to_x = nil
    s.think = s.think - dt
    if s.think <= 0 then
      local way = math.random(5)                 -- four directions, or a rest
      s.dx = way == 1 and -1 or way == 2 and 1 or 0
      s.dy = way == 3 and -1 or way == 4 and 1 or 0
      s.think = 0.5 + math.random() * 1.5
    end
  end
  local hit_x, hit_y = move.by(s, s.dx * SLIME_SPEED * dt, s.dy * SLIME_SPEED * dt)
  if hit_x or hit_y then s.think = 0 end

  -- Touching the player costs a heart, unless they were hit a moment ago.
  if move.overlap(player, s) and hurt:use() then
    hearts = hearts - 1
    cam:shake(2, 0.2)
    if hearts == 0 then
      finish("lost", story.t("caught"), story.t("retry"), SFX_LOST)
    else
      progress.sfx(SFX_HURT)
    end
  end
end

local function draw_level()
  cls(0)
  cam:apply()                   -- everything below scrolls with the camera
  map.draw(0)
  map.draw(1)
  for i = 1, #slimes do
    wobble:draw(slimes[i].x - 1, slimes[i].y - 2)
  end
  -- Just after a hit the player blinks.
  local safe = hurt:left()
  if safe <= 0 or math.floor(safe * 10) % 2 == 0 then
    walker:draw(player.x - 1, player.y - 2, player.flip)
    if wading then line(player.x - 1, player.y + 5, player.x + 6, player.y + 5, 7) end   -- the water line
  end
  drops:draw()

  camera()                      -- back to the screen for the top bar
  rectfill(0, 0, W, 11, 32)
  for i = 1, HEARTS do
    spr(i <= hearts and HEART or NO_HEART, 4 + (i - 1) * 9, 2)
  end
  -- The top bar needs no words, so it reads the same in either language:
  -- hearts, the level, gems found, a drop while wet, and the clock.
  print(level_text, 40, 2, 10)
  spr(GEM, 104, 2)
  print(found_text, 114, 2, 7)
  if wet > 0 then circfill(212, 6, 2, 12) pset(212, 2, 12) pset(212, 3, 12) end
  print(time_text, 316 - text.width(time_text), 2, time_left <= 10 and 8 or 7)
end

scene.add("play", {
  enter = start,
  update = function(dt)
    if input.pressed("start") then
      scene.push("pause")
      return
    end
    timer.update(dt)            -- runs the hurt and drip cooldowns
    drops:update(dt)
    move_player(dt)
    for i = 1, #slimes do
      if playing then move_slime(slimes[i], dt) end
    end
    wobble:update(dt)

    if playing then
      time_left = time_left - dt
      if time_left <= 0 then
        time_left = 0
        finish("lost", story.t("out_of_time"), story.t("retry"), SFX_LOST)
      end
    end
    -- Build the clock's text once a second, not sixty times.
    local seconds = math.ceil(time_left)
    if seconds ~= shown_seconds then
      shown_seconds = seconds
      time_text = text.clock(seconds)
    end

    cam:update(player.x + 3, player.y + 2, dt)
  end,
  draw = draw_level,
})

-- Drawn over the level, which stands still beneath it.
scene.add("pause", {
  enter = function()
    music_pause(true)           -- the tune waits too, and carries on from where it was
    progress.sfx(SFX_PAUSE)
  end,
  update = function(dt)
    if input.pressed("start") then
      music_pause(false)
      progress.sfx(SFX_RESUME)
      scene.pop()
    elseif input.pressed("select") then        -- leave for the title screen
      music_pause(false)
      music_stop()
      scene.go("title")
    end
  end,
  draw = function()
    local a, b = story.t("paused"), story.t("resume")
    local w = math.max(text.width(a), text.width(b)) + 24
    local h = text.height(a) + text.height(b) + 14
    local y = 120 - h // 2
    rectfill(160 - w // 2, y, w, h, 32)
    rect(160 - w // 2, y, w, h, 7)
    text.center(a, y + 5, 7)
    text.center(b, y + 9 + text.height(a), 6)
  end,
})

-- The end of a level, drawn over it: on to the next, or try again.
local ending = { how = "", message = "", prompt = "" }
scene.add("over", {
  enter = function(how, message, prompt)
    ending.how, ending.message, ending.prompt = how, message, prompt
  end,
  update = function(dt)
    if transition.busy() or not (input.pressed("a") or input.pressed("start")) then return end
    local n, full = level, true                         -- this level again
    if ending.how == "next" then n, full = level + 1, false
    elseif ending.how == "won" then n = 1 end           -- from the beginning
    transition.through(0.5, function() scene.go("play", n, full) end)
  end,
  draw = function()
    local colour = ending.how == "lost" and 8 or 10
    local w = math.max(200, math.max(text.width(ending.message), text.width(ending.prompt)) + 24)
    local h = text.height(ending.message) + text.height(ending.prompt) + 18
    local y = 118 - h // 2
    rectfill(160 - w // 2, y, w, h, 32)
    rect(160 - w // 2, y, w, h, colour)
    text.center(ending.message, y + 6, colour)
    text.center(ending.prompt, y + 12 + text.height(ending.message), 7)
  end,
})

return { levels = #LEVELS }
