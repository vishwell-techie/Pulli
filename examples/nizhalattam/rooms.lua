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
--                             the stories ("end"): main.lua ends the run
--   rooms.shop, rooms.shop_x  the room's stall or box (stall.lua, box.lua),
--                             or the halfway tear (pick.lua), and where it
--                             stands; nil in other rooms
--   rooms.want(name)          a module wanted in this room after all (the
--                             role picker, pick.lua): let go with the room
--   rooms.pick                the role picker, once wanted (or at the tear)
--   rooms.started             set when Komali steps from the Courtyard into
--                             the first story: main.lua begins the run
--   rooms.STORIES, MIDDLE     the stories: their first rooms; those made so
--                             far that come between the first and the last
--
-- A story's last door leads "next": into the next story in the run's order
-- (run.order), or to the halfway tear after the middle one, or out ("end")
-- after the last.
--
-- A room is a map of its own, drawn with its own tile sheet. Its doors are
-- markers on layer 1, taken in the order the map is read (row by row), and
-- ROOMS says where each leads. Going through one, the screen fades out, the
-- next room is loaded behind it, and the rooms beyond that room's doors,
-- with their sheets, are read ahead (`preload`), so nothing is read while
-- Komali plays. A fight room's doors stay shut until its shadows are torn.
-- Code is kept only where it is used: a story's own shadows (its cast) in
-- its rooms, a boss in his room, the stall and the box in theirs; it is read
-- ahead behind the doors too, and let go when Komali leaves.

local shadows = require("shadows")
local fight   = require("fight")
local run     = require("run")
local fx      = require("fx")
local C       = require("colours")
local PLACES  = require("places")

local rooms = { name = nil, w = 0, h = 0, ended = false, stall_x = nil, box_x = nil, floor_y = 0 }

-- Each room: its place (whose colours it is drawn in: the Courtyard, the
-- Screen by default, the forest), its tile sheet and its background, where
-- its doors lead (in the order the map is read), whether it is a fight room
-- (its doors shut until its shadows are torn), whether its shadows strike
-- softly (a lesson), the hint shown on the cloth with the buttons it names,
-- and the code it needs: its story's shadows (cast), its boss (and his
-- sheet), its stall or box (shop), arrows (shots.lua). A boss's room says
-- which hint follows his fall (taught).
-- (A room takes what it does not say from its story's defaults, through a
-- metatable, so each room's own table stays small; the buttons a hint names
-- are a string, "left right a".)
local SCREEN = { __index = { place = "screen", sheet = "screen.kolam", bg = "bg_screen.kolam", story = "screen" } }
local FOREST = { __index = { place = "forest", sheet = "forest.kolam", bg = "bg_forest.kolam", story = "forest",
                             cast = "forest" } }
local NONE = { __index = { place = "forest", sheet = "forest.kolam", bg = "bg_forest.kolam", story = "forest" } }
local SEA = { __index = { place = "sea", sheet = "sea.kolam", bg = "bg_sea.kolam", story = "sea", cast = "sea" } }
local S = function(def) return setmetatable(def, SCREEN) end
local F = function(def) return setmetatable(def, FOREST) end
local F0 = function(def) return setmetatable(def, NONE) end      -- a forest room with none of its shadows
local K = function(def) return setmetatable(def, SEA) end        -- (kadal, the sea)
local ROOMS = {
  ["map.ooru"]   = S{ place = "court", sheet = "court.kolam", bg = "bg_court.kolam", doors = { "test.ooru", "s1.ooru" },
                      hidden = 2,                -- the booth's glowing screen in the backdrop is the door
                      shop = "box", pick = true, -- (pick: read ahead, wanted later)
                      hint = "h_door", keys = "up" },
  -- the Screen, the first story: a lesson a room, then the boss
  ["s1.ooru"]    = S{ doors = { "s2.ooru" }, hint = "h_move", keys = "left right a", start = true,
                      hint2 = "h_high", keys2 = "a" },
  ["s2.ooru"]    = S{ doors = { "s3.ooru" }, fight = true, soft = true, hint = "h_strike", keys = "b" },
  ["s3.ooru"]    = S{ doors = { "s4.ooru" }, fight = true, soft = true, hint = "h_dodge", keys = "y" },
  ["s4.ooru"]    = S{ doors = { "s5.ooru" }, fight = true, soft = true, hint = "h_skill", keys = "x" },
  ["s5.ooru"]    = S{ doors = { "s6.ooru" }, fight = true, hint = "h_fight" },
  ["s6.ooru"]    = S{ doors = { "s7.ooru" }, hint = "h_stall", keys = "up", shop = "stall" },
  ["s7.ooru"]    = S{ doors = { "boss.ooru" }, hint = "h_pit" },
  ["boss.ooru"]  = S{ doors = { "next" }, fight = true, hint = "h_boss", boss = "veeran", pick = true,
                      taught = "h_swap", tkeys = "l r" },
  -- the Painted Forest, the second story
  ["f1.ooru"]    = F{ doors = { "f2.ooru" }, hint = "h_forest" },
  ["f2.ooru"]    = F{ doors = { "f3.ooru" }, fight = true, hint = "h_vine", keys = "a" },
  ["f3.ooru"]    = F{ doors = { "f2.ooru", "f4.ooru" }, hint = "h_wisp" },
  ["f4.ooru"]    = F0{ doors = { "f5.ooru" }, shop = "stall" },
  ["f5.ooru"]    = F{ doors = { "f6.ooru" }, fight = true },
  ["f6.ooru"]    = F{ doors = { "fboss.ooru" } },
  ["fboss.ooru"] = F0{ doors = { "next" }, fight = true, hint = "h_vil", pick = true, boss = "vil",
                       boss_sheet = "vil.kolam", arrows = true, taught = "h_aim", tkeys = "up down b" },
  -- the Leather Sea, the third (cast = false: a room with none of its shadows)
  ["k1.ooru"]    = K{ doors = { "k2.ooru" }, hint = "h_sea" },
  ["k2.ooru"]    = K{ doors = { "k3.ooru" }, fight = true, hint = "h_crab" },
  ["k3.ooru"]    = K{ doors = { "k4.ooru" }, hint = "h_boat" },
  ["k4.ooru"]    = K{ doors = { "k5.ooru" }, shop = "stall", cast = false },
  ["k5.ooru"]    = K{ doors = { "k6.ooru" }, fight = true, hint = "h_wave" },
  ["k6.ooru"]    = K{ doors = { "kboss.ooru" } },
  ["kboss.ooru"] = K{ doors = { "next" }, fight = true, hint = "h_aatta", pick = true, boss = "aattakkaari",
                      boss_sheet = "aatta.kolam", cast = false, taught = "h_dance", tkeys = "b x" },
  -- the halfway tear, after the middle story: the roles carried may be
  -- changed here, once a run
  ["tear.ooru"]  = S{ doors = { "next" }, story = "tear", shop = "pick", pick = true, hint = "h_tear", keys = "up" },
  -- the test rooms, off the Courtyard's side door
  ["test.ooru"]  = S{ sheet = "sprites.kolam", doors = { "climb.ooru" } },
  ["climb.ooru"] = S{ doors = { "arena.ooru", "test.ooru" } },
  ["arena.ooru"] = S{ doors = { "climb.ooru", "test.ooru" }, fight = true },
}
rooms.STORIES = { screen = "s1.ooru", forest = "f1.ooru", sea = "k1.ooru" }      -- each story's first room
rooms.MIDDLE = { "forest", "sea" }   -- made so far; the Battlefield and the Market to come
rooms.ROOMS = ROOMS
rooms.ACTORS = "actors.kolam"           -- Komali and the shadows: their own sheet

-- markers on layer 1
local START, SOLDIER, DOOR, DUMMY, INK, SCRAP, STALL, BOX, BOSS = 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008
local TEAR, LAST = 1012, 1017
local KIND = { [SOLDIER] = "soldier", [DUMMY] = "dummy", [INK] = "ink", [SCRAP] = "scrap",
               [1009] = "vine", [1010] = "moth", [1011] = "wisp",
               [1013] = "crab", [1014] = "wave", [1015] = "gull", [1016] = "boat", [1017] = "ferry" }
local FADE = 12                                 -- frames out, and as many in

local dx, dy, dto = {}, {}, {}                  -- the room's doors: cell, and where to
local fade_t, going = 0, nil

function rooms.def() return ROOMS[rooms.name] end

function rooms.locked()
  if not ROOMS[rooms.name].fight then return false end
  for _, s in ipairs(shadows.list) do
    if s.on and not s.prop then return true end         -- (not for a boat)
  end
  return false
end

local code = {}                                 -- the modules loaded for this room, by name

function rooms.want(name)
  if not code[name] then code[name] = require(name) end
  if name == "pick" then rooms.pick = code.pick end
  return code[name]
end

-- Where a story's last door leads, by the run's order.
function rooms.after(story)
  local order = run.order
  if story == "tear" then return rooms.STORIES[order[run.half + 1]] or "end" end
  for n, s in ipairs(order) do
    if s == story then
      if n == #order then return "end" end
      if n == run.half then return "tear.ooru" end
      return rooms.STORIES[order[n + 1]]
    end
  end
  return "end"
end
local backdrop_now                              -- the place's background, set once
local place_now                                 -- the place whose colours are set

-- A place's own colours: 20-31 and their shades 52-63 (places.lua).
local function colours_of(place)
  local p = PLACES[place]
  for n = 0, 23 do
    local h = n * 6
    palette(n < 12 and 20 + n or 52 + n - 12, tonumber(p:sub(h + 1, h + 2), 16),
            tonumber(p:sub(h + 3, h + 4), 16), tonumber(p:sub(h + 5, h + 6), 16))
  end
end

-- The code a room needs; what the last room needed and this one does not
-- is let go, with the kinds of shadow it added.
local function needs(def)
  for name, m in pairs(code) do
    if name ~= def.cast and name ~= def.boss and name ~= def.shop then
      for _, kind in ipairs(m.kinds or {}) do shadows.kinds[kind] = nil end
      unrequire(name)
      code[name] = nil
    end
  end
  for _, name in pairs({ def.cast, def.boss, def.shop }) do
    if name and not code[name] then code[name] = require(name) end
  end
end

function rooms.enter(name, from, body)
  local def = ROOMS[name]
  shadows.boss, shadows.beaten = nil, false
  needs(def)
  rooms.shop, rooms.pick = def.shop and code[def.shop], code.pick
  if def.start and from == "map.ooru" then rooms.started = true end
  map.load(name)
  preload(def.sheet, def.bg)
  -- the place's background: set once, and each frame starts from it (cls)
  if def.bg ~= backdrop_now then backdrop(def.bg) backdrop_now = def.bg end
  if def.place ~= place_now then colours_of(def.place) place_now = def.place end
  rooms.name = name
  local w, h = map.size()
  rooms.w, rooms.h = w * 8, h * 8
  shadows.clear()
  for n = #body.floors, 1, -1 do body.floors[n] = nil end
  shadows.soft = def.soft and 0.33 or 1
  fx.clear()
  fight.arrows(def.arrows)                      -- (and clears those in flight)
  rooms.stall_x, rooms.box_x, rooms.tear_x = nil, nil, nil
  for n = #dx, 1, -1 do dx[n], dy[n], dto[n] = nil, nil, nil end
  local sx, sy = 40, 200
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      local m = map.get(1, cx, cy)
      local x, y = cx * 8 + 4, cy * 8 + 8
      if m == START then sx, sy = x, y
      elseif KIND[m] then shadows.add(x, y, KIND[m])
      elseif m == BOSS then shadows.add(x, y, def.boss)
      elseif m == STALL then rooms.stall_x, rooms.floor_y = x, y
      elseif m == BOX then rooms.box_x, rooms.floor_y = x, y
      elseif m == TEAR then rooms.tear_x, rooms.floor_y = x, y
      elseif m == DOOR then
        local n = #dx + 1
        dx[n], dy[n], dto[n] = cx, cy, def.doors[n] == "next" and rooms.after(def.story) or def.doors[n]
      end
      if m >= START and m <= LAST then map.set(1, cx, cy, 0) end
    end
  end
  -- in at the door from where he came
  for n = 1, #dx do
    if from and dto[n] == from then sx, sy = dx[n] * 8 + 4, dy[n] * 8 + 8 end
  end
  rooms.shop_x = rooms.stall_x or rooms.box_x or rooms.tear_x
  body.place(sx, sy)
  -- the rooms beyond this one's doors, their sheets and their code, read
  -- ahead (past the last door, the Courtyard)
  for n = 1, #dto do
    local to = dto[n] == "end" and "map.ooru" or dto[n]
    local d = ROOMS[to]
    preload(to, d.sheet, d.bg)
    for _, m in pairs({ d.cast, d.boss, d.shop, d.pick and "pick" }) do if m then preload(m .. ".lua") end end
    if d.boss then preload("role_" .. d.boss .. ".lua") end      -- the role he lends
    if d.boss_sheet then preload(d.boss_sheet) end
    if d.arrows then preload("shots.lua") end
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

-- the stall and the Aasaan's box, drawn from the actors' sheet; the tear,
-- a rip in the cloth with the lamp blazing through
function rooms.draw_things()
  if rooms.tear_x then
    local x, y, f = rooms.tear_x, rooms.floor_y, stat("frame")
    for n = 0, 11 do
      local y0, y1 = y - 64 + n * 5, y - 59 + n * 5
      local x0 = x + ((n * 5) % 7 - 3) * 2
      local x1 = x + (((n + 1) * 5) % 7 - 3) * 2
      local w = 6 - math.abs(n - 6) // 2 + (f // 8 + n) % 2
      for d = -w, w do line(x0 + d, y0, x1 + d, y1, math.abs(d) < w - 2 and C.glow or math.abs(d) < w and C.lamp or C.ink) end
    end
  end
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
