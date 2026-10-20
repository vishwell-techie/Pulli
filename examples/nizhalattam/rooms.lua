-- rooms.lua — rooms, and the doors between them.
--
--   rooms.enter(name, from)   load a room; Komali comes in at the door from
--                             `from`, or at its start marker
--   rooms.update(input, body) once a frame: up at a door goes through it.
--                             True while the screen fades (the world waits)
--   rooms.draw_doors()        the doors, with the room's tiles
--   rooms.draw_things()       the stall and the Aasaan's box, with the actors
--   rooms.fade()              0 to 1, how dark the screen is
--   rooms.ended               set when Komali goes through the last door of
--                             a story ("end"): main.lua ends the run
--
-- A room is a map of its own, drawn with its own tile sheet. Its doors are
-- markers on layer 1, taken in the order the map is read (row by row), and
-- ROOMS says where each leads. Going through one, the screen fades out, the
-- next room is loaded behind it, and the rooms beyond that room's doors,
-- with their sheets, are read ahead (`preload`), so nothing is read while
-- Komali plays. A fight room's doors stay shut until its shadows are torn.

local shadows = require("shadows")
local fx      = require("fx")
local C       = require("colours")
local PLACES  = require("places")

local rooms = { name = nil, w = 0, h = 0, ended = false, stall_x = nil, box_x = nil, floor_y = 0 }

-- Each room: its place (whose colours it is drawn in: the Courtyard, or the
-- Screen by default), its tile sheet and its background, where its doors lead (in the order the map is
-- read), whether it is a fight room (its doors shut until its shadows are
-- torn), whether its shadows strike softly (a lesson), and the hint shown
-- on the cloth, with the buttons it names.
local SCREEN, COURT = "bg_screen.kolam", "bg_court.kolam"
local ROOMS = {
  ["map.ooru"]   = { place = "court", sheet = "court.kolam", bg = COURT, doors = { "test.ooru", "s1.ooru" },
                     hidden = 2,                -- the booth's glowing screen in the backdrop is the door
                     name = "hub",
                     hint = "h_door", keys = { "up" } },
  -- the Screen, the first story: a lesson a room, then the boss
  ["s1.ooru"]    = { sheet = "screen.kolam", doors = { "s2.ooru" }, hint = "h_move", keys = { "left", "right", "a" },
                     hint2 = "h_high", keys2 = { "a" } },
  ["s2.ooru"]    = { sheet = "screen.kolam", doors = { "s3.ooru" }, fight = true, soft = true,
                     hint = "h_strike", keys = { "b" } },
  ["s3.ooru"]    = { sheet = "screen.kolam", doors = { "s4.ooru" }, fight = true, soft = true,
                     hint = "h_dodge", keys = { "y" } },
  ["s4.ooru"]    = { sheet = "screen.kolam", doors = { "s5.ooru" }, fight = true, soft = true,
                     hint = "h_skill", keys = { "x" } },
  ["s5.ooru"]    = { sheet = "screen.kolam", doors = { "s6.ooru" }, fight = true, hint = "h_fight", keys = {} },
  ["s6.ooru"]    = { sheet = "screen.kolam", doors = { "s7.ooru" }, hint = "h_stall", keys = { "up" } },
  ["s7.ooru"]    = { sheet = "screen.kolam", doors = { "boss.ooru" }, hint = "h_pit", keys = {} },
  ["boss.ooru"]  = { sheet = "screen.kolam", doors = { "end" }, fight = true, hint = "h_boss", keys = {},
                     boss = "veeran" },
  -- the test rooms, off the Courtyard's side door
  ["test.ooru"]  = { sheet = "sprites.kolam", doors = { "climb.ooru" } },
  ["climb.ooru"] = { sheet = "screen.kolam", doors = { "arena.ooru", "test.ooru" } },
  ["arena.ooru"] = { sheet = "screen.kolam", doors = { "climb.ooru", "test.ooru" }, fight = true },
}
for _, def in pairs(ROOMS) do def.bg, def.place = def.bg or SCREEN, def.place or "screen" end
rooms.ROOMS = ROOMS
rooms.ACTORS = "actors.kolam"           -- Komali and the shadows: their own sheet

-- markers on layer 1
local START, SOLDIER, DOOR, DUMMY, INK, SCRAP, STALL, BOX, BOSS = 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008
local KIND = { [SOLDIER] = "soldier", [DUMMY] = "dummy", [INK] = "ink", [SCRAP] = "scrap", [BOSS] = "veeran" }
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

local boss_code                                 -- the boss module loaded, if any
local backdrop_now                              -- the place's background, set once
local place_now                                 -- the place whose colours are set

-- A place's own colours: 20-31 and their shades 52-63 (places.lua).
local function colours_of(place)
  local p = PLACES[place]
  for n = 0, 23 do
    palette(n < 12 and 20 + n or 52 + n - 12, p[n * 3 + 1], p[n * 3 + 2], p[n * 3 + 3])
  end
end

function rooms.enter(name, from, body)
  local def = ROOMS[name]
  -- a boss's code is kept only in its room
  if boss_code and boss_code ~= def.boss then
    shadows.kinds[boss_code] = nil
    unrequire(boss_code)
    boss_code = nil
  end
  shadows.boss, shadows.beaten = nil, false
  if def.boss then boss_code = def.boss; require(def.boss) end
  map.load(name)
  preload(def.sheet, def.bg)
  -- the place's background: set once, and each frame starts from it (cls)
  if def.bg ~= backdrop_now then backdrop(def.bg) backdrop_now = def.bg end
  if def.place ~= place_now then colours_of(def.place) place_now = def.place end
  rooms.name = name
  local w, h = map.size()
  rooms.w, rooms.h = w * 8, h * 8
  shadows.clear()
  shadows.soft = def.soft and 0.33 or 1
  fx.clear()
  rooms.stall_x, rooms.box_x = nil, nil
  for n = #dx, 1, -1 do dx[n], dy[n], dto[n] = nil, nil, nil end
  local sx, sy = 40, 200
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      local m = map.get(1, cx, cy)
      local x, y = cx * 8 + 4, cy * 8 + 8
      if m == START then sx, sy = x, y
      elseif KIND[m] then shadows.add(x, y, KIND[m])
      elseif m == STALL then rooms.stall_x, rooms.floor_y = x, y
      elseif m == BOX then rooms.box_x, rooms.floor_y = x, y
      elseif m == DOOR then
        local n = #dx + 1
        dx[n], dy[n], dto[n] = cx, cy, def.doors[n]
      end
      if m >= START and m <= BOSS then map.set(1, cx, cy, 0) end
    end
  end
  -- in at the door from where he came
  for n = 1, #dx do
    if from and dto[n] == from then sx, sy = dx[n] * 8 + 4, dy[n] * 8 + 8 end
  end
  body.place(sx, sy)
  -- the rooms beyond this one's doors, and their sheets, read ahead (past
  -- a story's last door, the Courtyard)
  for n = 1, #dto do
    local to = dto[n] == "end" and "map.ooru" or dto[n]
    preload(to, ROOMS[to].sheet, ROOMS[to].bg)
    if ROOMS[to].boss then preload(ROOMS[to].boss .. ".lua") end
  end
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
    if n and not rooms.locked() then
      if dto[n] == "end" then rooms.ended = true return true end
      going, fade_t = dto[n], 0
      return true
    end
  end
  return false
end

function rooms.fade()
  if not going then return 0 end
  return fade_t < FADE and fade_t / FADE or (FADE * 2 - fade_t) / FADE
end

-- a door: a curtained arch in a carved frame, lamplight through the gap;
-- barred while it is shut
function rooms.draw_doors()
  local shut = rooms.locked()
  for n = 1, #dx do if n ~= rooms.def().hidden then
    local x, y = dx[n] * 8 - 6, dy[n] * 8 - 24
    rectfill(x, y + 4, 20, 28, C.wood)
    rectfill(x + 2, y + 2, 16, 4, C.wood)
    rectfill(x + 4, y, 12, 4, C.wood)
    rectfill(x + 2, y + 6, 16, 26, shut and C.ink or C.lamp)
    rectfill(x + 3, y + 6, 6, 26, shut and C.navy or C.red)      -- the curtains, drawn aside
    rectfill(x + 11, y + 6, 6, 26, shut and C.navy or C.red)
    for c = 0, 2 do line(x + 4 + c * 2, y + 7, x + 4 + c * 2, y + 31, shut and C.ink or C.oxblood) end
    line(x + 2, y + 5, x + 17, y + 5, C.marigold)
    pset(x + 9, y + 1, C.lamp) pset(x + 10, y + 1, C.lamp)
    if shut then
      line(x + 1, y + 14, x + 18, y + 14, C.silver) line(x + 1, y + 22, x + 18, y + 22, C.silver)
    end
  end end
end

-- the stall and the Aasaan's box, drawn from the actors' sheet
function rooms.draw_things()
  if rooms.stall_x then spr(774, rooms.stall_x - 16, rooms.floor_y - 32, 4, 4) end
  if rooms.box_x then
    spr(771, rooms.box_x - 12, rooms.floor_y - 16, 3, 2)
    -- the Aasaan beside his box, nodding now and then
    spr(512 + (8 + stat("frame") // 90 % 2) * 3, rooms.box_x + 12, rooms.floor_y - 32, 3, 4, true)
  end
end

-- Is Komali (k) standing at x: the stall, or the box?
function rooms.near(x, k)
  return x ~= nil and math.abs(x - (k.x + k.w / 2)) < 16 and k.ground
end

return rooms
