-- challenge.lua — a story's challenge room, behind the secret door on a
-- high ledge in its stall room (only the double jump reaches it). The room
-- is built when Komali steps in, from the run's seed and the skills he has,
-- in the walls-only map challenge.tmx: rooms.lua calls challenge.build
-- before it reads the room's markers, and keeps this as the room's "shop":
-- the chest at the far end.
--
--   challenge.build(def, k)     lay the room out: k is Komali (body.k): his
--                               double jump, wall jump, second dodge
--   challenge.open()            up at the chest: its reward, once a run
--                               (returns how main.lua shows it)
--   challenge.update(input, body), draw(body), is_open()   as a shop's
--
-- Every skill he has is wanted somewhere in the room: with the double
-- jump, higher steps and wider pits; with the wall jump, a cliff climbed
-- between two walls; with the second dodge, a long pit under a low roof.
-- What he lacks is never asked of him. The shadows here leave nothing when
-- torn (shadows.nodrop). The reward is oil, mai or a charm; in hard mode,
-- while the story's page is not yet found, the page, and nothing else.

local run   = require("run")
local fight = require("fight")
local C     = require("colours")

local challenge = {}

local W, H = 150, 30
local SOLID = 2                                -- (a solid tile; dress picks each one's look)
local DOOR, CHEST = 1002, 1029
-- the story's shadows, by marker (rooms.lua's KIND), those that fly marked
local CAST = {
  screen = { 1001, 1004, 1005 }, forest = { 1009, 1010, 1011 }, sea = { 1013, 1014, 1015 },
  flags = { 1001, 1019, 1020 }, masks = { 1021, 1022, 1001 }, palace = { 1024, 1025, 1026 },
}
local FLY = { [1005] = true, [1010] = true, [1011] = true, [1015] = true, [1026] = true }

-- the room is laid out in the map itself (no table of cells: the heap is
-- small): tiles in layer 0, markers in layer 1
local state = 1
local function rand(n)                         -- the room's own numbers, from its seed
  state = state ~ (state << 13)
  state = state ~ (state >> 17)
  state = state ~ (state << 5)
  return (state & 0x7fffffff) % n + 1
end

local function set(x, y, v) if x >= 0 and x < W and y >= 0 and y < H then map.set(0, x, y, v) end end
local function floor(x0, x1, fy)               -- solid from row fy + 1 down
  for x = x0, x1 do for y = fy + 1, H - 1 do set(x, y, SOLID) end end
end
local function mark(x, y, m) map.set(1, x, y, m) end

local function enemy(x, fy, story)
  local list = CAST[story] or CAST.screen
  local m = list[rand(#list)]
  mark(x, FLY[m] and fy - 4 or fy, m)
end

-- The pieces of the course: each lays out columns from x and returns where
-- the next begins, and the floor's level there (fy: the row Komali's feet
-- are in).
local P = {}
function P.run(x, fy, s)                       -- level ground, a shadow on it
  local n = 7 + rand(4)
  floor(x, x + n - 1, fy)
  if rand(3) > 1 then enemy(x + n // 2, fy, s.story) end
  return x + n, fy
end
function P.step(x, fy, s)                      -- up (as high as he can climb) or down
  local up = fy > 12 and (fy > 20 or rand(2) == 1)
  local d = up and rand(s.rise) or (1 + rand(4))
  local nfy = math.max(8, math.min(25, up and fy - d or fy + d))
  local n = 6 + rand(3)
  floor(x, x + n - 1, nfy)
  return x + n, nfy
end
function P.gap(x, fy, s)                       -- a pit, as wide as he can jump
  local w = s.gap - rand(2) + 1
  local n = 6
  floor(x + w, x + w + n - 1, fy)
  return x + w + n, fy
end
function P.shaft(x, fy, s)                     -- (the wall jump) a cliff ten tiles high, and a
  if fy < 22 then                              -- wall hanging before it to bounce between; first,
    floor(x, x + 11, 25)                       -- down to the bottom, far from where he was (no
    x, fy = x + 12, 25                         -- jumping across to the cliff's top)
  end
  challenge.shaft_at = { x + 4, fy, fy - 10 }    -- (where: for the tests)
  floor(x, x + 5, fy)                          -- under the hanging wall, and between
  for y = fy - 14, fy - 3 do set(x + 2, y, SOLID) end
  local top = fy - 10
  floor(x + 6, x + 12, top)                    -- the cliff, and its top
  return x + 13, top
end
function P.tunnel(x, fy, s)                    -- (the second dodge) a long pit under a roof; the far
  fy = math.min(fy, 24)                        -- side a tile lower: he sinks a little between rolls
  challenge.tunnel_at = { x + 1, fy, x + 17 }
  floor(x, x + 3, fy)
  for xx = x + 2, x + 16 do for y = 0, fy - 3 do set(xx, y, SOLID) end end
  floor(x + 15, x + 20, fy + 1)
  return x + 21, fy + 1
end
local WIDE = { shaft = 31, tunnel = 21, high = 16 }    -- the most each skill's piece takes
function P.high(x, fy, s)                      -- (the double jump) a step only it climbs, with open
  local nfy = math.max(8, fy - 5)              -- ground before it: no wall near to jump from
  floor(x, x + 8, fy)
  floor(x + 9, x + 15, nfy)
  return x + 16, nfy
end

-- The tiles as drawn: each solid cell the tile that fits its neighbours,
-- a thin floor its ends (as rooms.py dresses a room it writes).
local function dress()
  local function solid(x, y) return x < 0 or x >= W or y < 0 or y >= H or map.flags(map.get(0, x, y)) & 1 ~= 0 end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if solid(x, y) then                      -- (a look changed keeps the cell solid for its neighbours)
        local l, r, t = solid(x - 1, y), solid(x + 1, y), nil
        if not solid(x, y - 1) then t = (not l and not r) and 7 or not l and 5 or not r and 6 or 1
        else t = not l and 8 or not r and 9 or ((x * 7 + y * 13) % 23 == 0 and 10 or 2) end
        map.set(0, x, y, t)
      end
    end
  end
end

function challenge.build(def, k)
  for y = 0, H - 1 do for x = 0, W - 1 do map.set(0, x, y, 0) map.set(1, x, y, 0) end end
  for y = 0, H - 1 do set(0, y, SOLID) set(1, y, SOLID) set(W - 2, y, SOLID) set(W - 1, y, SOLID) end
  local seed = (run.seed or 0) * 31
  for c in def.story:gmatch(".") do seed = (seed * 31 + c:byte()) % 1000003 end
  state = (seed + 1) * 0x9e3779b1 | 1
  for _ = 1, 4 do rand(2) end
  local s = { story = def.story, rise = k.double and 5 or 3, gap = k.double and 8 or 5 }
  -- the pieces: level ground, steps and pits, and each skill he has once,
  -- somewhere among them (never first); the skills' pieces always find
  -- room: fillers are left out when only that room is left
  local list, FILL = {}, { "run", "step", "gap" }
  for n = 1, 9 do list[n] = FILL[rand(3)] end
  local need = 0
  for _, sk in ipairs({ { k.double, "high" }, { k.walljump, "shaft" }, { k.second, "tunnel" } }) do
    if sk[1] then
      table.insert(list, 1 + rand(#list), sk[2])
      need = need + WIDE[sk[2]]
    end
  end
  local x, fy = 2, 25
  floor(2, 9, fy)
  mark(5, fy, DOOR)                            -- in (and back) at the start
  x = 10
  for _, piece in ipairs(list) do
    if WIDE[piece] then
      x, fy = P[piece](x, fy, s)
      need = need - WIDE[piece]
    elseif x + 11 + need < W - 16 then
      x, fy = P[piece](x, fy, s)
    end
  end
  floor(x, W - 3, fy)                          -- the end: the chest, and a door back
  mark(x + 4, fy, CHEST)
  mark(W - 6, fy, DOOR)
  dress()
end

-- ---- the chest ------------------------------------------------------------

local said
local CHARMS = { "bell", "spool", "torn", "soot", "drum" }

function challenge.is_open() return false end
function challenge.update(i, body) return false end

function challenge.open()
  local story = require("rooms").def().story
  if run.claimed[story] then return nil end
  run.claimed[story] = true
  local lines = require("lines")
  -- in hard mode, the story's page while it is not found: that alone
  if run.hard() and not run.page_found(story) then
    local pages = require("pages")
    local n = run.find_page(story)
    local a, b = lines.t("page_n", n, pages.COUNT), pages.text(n)
    unrequire("pages")
    return "card", a, b
  end
  local r = rand(10)
  if r <= 4 then                               -- oil
    local n = 6 + rand(9)
    run.add_oil(n)
    return "say", lines.t("oil", n)
  end
  if r <= 7 and #run.charms < 2 + math.min(1, run.data.repairs.r_charm3 or 0) then   -- a charm not carried
    local free = {}
    for _, c in ipairs(CHARMS) do if not run.charm(c) then free[#free + 1] = c end end
    if #free > 0 then
      local c = free[rand(#free)]
      run.charms[#run.charms + 1] = c
      return "say", lines.t(c) .. ": " .. lines.t(c .. "_d")
    end
  end
  local n = 100 + rand(10) * 10                -- mai
  fight.mai = fight.mai + n
  return "say", lines.t("mai") .. " +" .. n
end

function challenge.draw(body) end            -- (the chest is drawn with the room: rooms.draw_things)

return challenge
