-- rooms.lua — rooms, and the doors between them.
--
--   rooms.enter(name, from)   load a room; Komali comes in at the door from
--                             `from`, or at its start marker
--   rooms.update(input, body) once a frame: up at a door goes through it.
--                             True while the screen fades (the world waits)
--   rooms.draw_doors()        the doors, with the room's tiles
--   rooms.fade()              0 to 1, how dark the screen is
--
-- A room is a map of its own, drawn with its own tile sheet. Its doors are
-- markers on layer 1, taken in the order the map is read (row by row), and
-- ROOMS says where each leads. Going through one, the screen fades out, the
-- next room is loaded behind it, and the rooms beyond that room's doors,
-- with their sheets, are read ahead (`preload`), so nothing is read while
-- Komali plays. A fight room's doors stay shut until its shadows are torn.

local shadows = require("shadows")
local fx      = require("fx")

local rooms = { name = nil, w = 0, h = 0 }

local ROOMS = {
  ["map.ooru"]   = { sheet = "sprites.kolam", doors = { "climb.ooru" } },
  ["climb.ooru"] = { sheet = "paper.kolam", doors = { "arena.ooru", "map.ooru" } },
  ["arena.ooru"] = { sheet = "paper.kolam", doors = { "climb.ooru", "map.ooru" }, fight = true },
}
rooms.ROOMS = ROOMS
rooms.ACTORS = "actors.kolam"           -- Komali and the shadows: their own sheet

local START, SOLDIER, DOOR = 1000, 1001, 1002   -- markers on layer 1
local FADE = 12                                 -- frames out, and as many in

local dx, dy, dto = {}, {}, {}                  -- the room's doors: cell, and where to
local fade_t, going = 0, nil

function rooms.def() return ROOMS[rooms.name] end

function rooms.locked()
  if not ROOMS[rooms.name].fight then return false end
  for _, s in ipairs(shadows.list) do
    if s.on then return true end
  end
  return false
end

function rooms.enter(name, from, body)
  local def = ROOMS[name]
  map.load(name)
  rooms.name = name
  local w, h = map.size()
  rooms.w, rooms.h = w * 8, h * 8
  shadows.clear()
  fx.clear()
  for n = #dx, 1, -1 do dx[n], dy[n], dto[n] = nil, nil, nil end
  local sx, sy = 40, 200
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      local m = map.get(1, cx, cy)
      if m == START then sx, sy = cx * 8 + 4, cy * 8 + 8
      elseif m == SOLDIER then shadows.add(cx * 8 + 4, cy * 8 + 8)
      elseif m == DOOR then
        local n = #dx + 1
        dx[n], dy[n], dto[n] = cx, cy, def.doors[n]
      end
      if m >= START and m <= DOOR then map.set(1, cx, cy, 0) end
    end
  end
  -- in at the door from where he came
  for n = 1, #dx do
    if from and dto[n] == from then sx, sy = dx[n] * 8 + 4, dy[n] * 8 + 8 end
  end
  body.place(sx, sy)
  -- the rooms beyond this one's doors, and their sheets, read ahead
  for n = 1, #dto do preload(dto[n], ROOMS[dto[n]].sheet) end
end

-- The door he stands at, if any.
local function at_door(k)
  local cx, feet = k.x + k.w / 2, k.y + k.h
  for n = 1, #dx do
    if math.abs(cx - (dx[n] * 8 + 4)) < 8 and math.abs(feet - (dy[n] * 8 + 8)) < 2 then return n end
  end
end

function rooms.update(i, body)
  if going then
    fade_t = fade_t + 1
    if fade_t == FADE then rooms.enter(going, rooms.name, body) end
    if fade_t >= FADE * 2 then going, fade_t = nil, 0 end
    return true
  end
  local k = body.k
  if i.door and k.ground and k.dodge == 0 then
    local n = at_door(k)
    if n and not rooms.locked() then going, fade_t = dto[n], 0 return true end
  end
  return false
end

function rooms.fade()
  if not going then return 0 end
  return fade_t < FADE and fade_t / FADE or (FADE * 2 - fade_t) / FADE
end

-- a door: a cloth curtain in a wooden frame; barred while it is shut
function rooms.draw_doors()
  local shut = rooms.locked()
  for n = 1, #dx do
    local x, y = dx[n] * 8 - 4, dy[n] * 8 - 16
    rectfill(x, y, 16, 24, 36)
    rectfill(x + 2, y + 2, 12, 22, shut and 33 or 2)
    for c = 0, 2 do line(x + 4 + c * 4, y + 3, x + 4 + c * 4, y + 23, shut and 38 or 18) end
    if shut then line(x, y + 12, x + 15, y + 12, 6) end
  end
end

return rooms
