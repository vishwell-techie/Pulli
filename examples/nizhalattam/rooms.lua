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
--   rooms.came                set when Komali has come through a door into
--                             a room (not when a room is entered otherwise):
--                             main.lua keeps the run there; rooms.from is
--                             the room he came from
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
local lines   = require("lines")
local fight   = require("fight")
local run     = require("run")
local fx      = require("fx")
local move    = require("move")
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
local S = function(def) return setmetatable(def, SCREEN) end
local ROOMS = {
  ["map.ooru"]   = S{ place = "court", sheet = "court.kolam", bg = "bg_court.kolam", doors = { "test.ooru", "s1.ooru" },
                      hidden = 2,                -- the booth's glowing screen in the backdrop is the door
                      shop = "box", pick = true, -- (pick: read ahead, wanted later)
                      hint = "h_door", keys = "up" },
  -- the halfway tear, after the middle story: the roles carried may be
  -- changed here, once a run
  ["tear.ooru"]  = S{ doors = { "next" }, story = "tear", shop = "pick", pick = true, hint = "h_tear", keys = "up" },
  -- the test rooms, off the Courtyard's side door
  ["test.ooru"]  = S{ sheet = "sprites.kolam", doors = { "climb.ooru" } },
  ["climb.ooru"] = S{ doors = { "arena.ooru", "test.ooru" } },
  ["arena.ooru"] = S{ doors = { "climb.ooru", "test.ooru" }, fight = true },
}
-- Each story's rooms are in a file of their own (rooms_forest.lua, ...),
-- read when a room of it is wanted, and let go once Komali is neither in
-- the story nor at a door into it: only the Courtyard's, the tear's and the
-- test rooms are always kept. A room's name says its story: its first
-- letter, then a digit or "boss" (and "boss.ooru" is the Screen's).
local FILE = "rooms_"                   -- (a name made, so pack does not take "rooms_" for a module)
local LETTER = { s = "screen", f = "forest", k = "sea", b = "flags", m = "masks", p = "palace" }
local held = {}                         -- the stories' room tables read now, by story

local function story_of(name)
  if name == "boss.ooru" then return "screen" end
  if name:find("^%l%d") or name:find("^%lboss") then return LETTER[name:sub(1, 1)] end
end

setmetatable(ROOMS, { __index = function(_, name)
  local story = story_of(name)
  if not story then return nil end
  if not held[story] then held[story] = require(FILE .. story) end
  return held[story][name]
end })

-- let go the room tables of stories not in `keep` (a room's def, and the
-- defs its doors lead to)
local function let_go(a, b, c)
  for story in pairs(held) do
    if story ~= a and story ~= b and story ~= c then
      held[story] = nil
      unrequire(FILE .. story)
    end
  end
end

rooms.STORIES = { screen = "s1.ooru", forest = "f1.ooru", sea = "k1.ooru", flags = "b1.ooru",
                  masks = "m1.ooru", palace = "p1.ooru" }   -- each story's first room
rooms.MIDDLE = { "forest", "sea", "flags", "masks" }     -- the stories between the Screen and the Palace
rooms.LAST = "palace"
rooms.ROOMS = ROOMS
rooms.ACTORS = "actors.kolam"           -- Komali and the shadows: their own sheet

-- markers on layer 1
local START, SOLDIER, DOOR, DUMMY, INK, SCRAP, STALL, BOX, BOSS = 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008
local TEAR, LAST = 1012, 1026
local KIND = { [SOLDIER] = "soldier", [DUMMY] = "dummy", [INK] = "ink", [SCRAP] = "scrap",
               [1009] = "vine", [1010] = "moth", [1011] = "wisp",
               [1013] = "crab", [1014] = "wave", [1015] = "gull", [1016] = "boat", [1017] = "ferry",
               [1018] = "archer", [1019] = "flag", [1020] = "drum",
               [1021] = "thief", [1022] = "juggler", [1023] = "twin",
               [1024] = "lampguard", [1025] = "mirror", [1026] = "cinder" }
-- In hard mode every other one of these has a second beside it.
local MORE = { soldier = true, ink = true, scrap = true, vine = true, moth = true, wisp = true,
               crab = true, wave = true, gull = true, archer = true, thief = true,
               lampguard = true, mirror = true, cinder = true }
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

-- a second shadow of a kind, a little way off the marker: where there is
-- room for it, and a floor if the marker has one
local function another(x, y, kind)
  local floor = move.blocked(x, y, 1, 1)
  for _, d in ipairs({ -18, 18 }) do
    local x2 = x + d
    if not move.blocked(x2 - 5, y - 20, 10, 20) and (not floor or move.blocked(x2, y, 1, 1)) then
      shadows.add(x2, y, kind)
      return
    end
  end
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

-- A place's colours and background, set if they are not set already (the
-- title sets its own this way too).
function rooms.dress(place, bg)
  if bg ~= backdrop_now then backdrop(bg) backdrop_now = bg end
  if place ~= place_now then colours_of(place) place_now = place end
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
  rooms.dress(def.place, def.bg)
  rooms.name = name
  local w, h = map.size()
  rooms.w, rooms.h = w * 8, h * 8
  shadows.clear()
  for n = #body.floors, 1, -1 do body.floors[n] = nil end
  shadows.soft = def.soft and 0.33 or 1
  -- hard mode: shadows hit harder, have more health, come more of them,
  -- and every boss is a shadow; before that, so is a saved puppet's
  local hard = run.hard()
  shadows.hard, body.harder = hard, hard and 1.5 or 1
  shadows.shade = def.boss ~= nil and def.boss ~= "king" and (hard or run.saved(def.boss))
  local more = 0
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
      elseif KIND[m] then
        shadows.add(x, y, KIND[m])
        if hard and MORE[KIND[m]] then
          more = more + 1
          if more % 2 == 1 then another(x, y, KIND[m]) end
        end
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
    if d.boss and d.boss ~= "king" then preload("role_" .. d.boss .. ".lua") end      -- the role he lends
    if d.boss_sheet then preload(d.boss_sheet) end
    if d.arrows then preload("shots.lua") end
  end
  -- the room tables of the stories it is in and leads to are kept; the
  -- story's own words come with its rooms
  local a = dto[1] and story_of(dto[1] == "end" and "map.ooru" or dto[1])
  local b = dto[2] and story_of(dto[2])
  let_go(def.story, a, b)
  lines.story = held[def.story] and held[def.story].words
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
    if fade_t == FADE then
      rooms.from = rooms.name
      rooms.enter(going, rooms.name, body)
      rooms.came = true
    end
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
