-- world.lua — the world Kayal walks through: one region (chapter) at a time.
--
-- A region is a module (ch0.lua ... ch6.lua) that names its map and music
-- and adds what makes it different. world.lua does what the regions share:
-- Kayal and Minmini, slimes, lamps, people, things to pick up, gates and
-- keys, switches and stepping stones, water and thorns, mirrors and beams of
-- light, the camera, night and cut-scenes. Slimes chase straight, sliding
-- along walls; the SDK's pathfind would be smarter, but costs memory this
-- game needs more. play.lua puts a world on screen.
--
-- Maps come from Tiled. Layer 0 is the ground; layer 1 is drawn in front of
-- everyone (tree tops) and carries markers, the tiles of row 15 of the
-- sheet, which say where Kayal starts and where people and things go. They
-- are read and taken off when a map loads.
--
-- A region is a table that may hold:
--   map, music, dark, pieces  its map, music, whether it is dark but for
--                             lights, and which ruby pieces (1 to 7) its
--                             piece markers are
--   night                     the map drawn in the darker half of the palette
--   preload                   other parts it uses ("top.ooru", "music 7"), read
--                             with its map and music behind the loading screen
--   lines                     what each person says: lines.paati = "key"
--   start(w), update(w, dt), leave(w)
--   talk(w, npc)              when Kayal speaks to someone, instead of lines
--   exit(w)                   when Kayal reaches an exit marker
--   hint(w)                   Minmini's advice, a story key
--   event(w, what, thing)     "got" a thing, "lit" a lamp, "switch" a group,
--                             "flare". For a ruby piece, "got" comes at the
--                             end of the piece's cut-scene, inside it, so
--                             the region may carry the scene on with
--                             script steps.
--   use(w, cx, cy, tile)      A at a tile nothing else answered
--   lights(w), draw(w), draw_top(w), hud(w)
--
-- Memory is the game's tightest limit, and every Lua function costs some
-- for as long as the game runs, so this file keeps to a few large functions.

local core     = require("core")
local move     = require("move")
local talk     = require("talk")
local script   = require("script")
local dark     = require("dark")
local fx       = require("fx")
local story    = require("story")
local progress = require("progress")

local w = {}

-- Tile flags and the tiles the world knows by number (see sprites.tsx).
local SOLID, WATER, HURT, DEEP, DARK, LAMP, MIRROR, BEAM = 1, 2, 4, 8, 16, 32, 64, 128
w.SOLID, w.WATER, w.HURT, w.DEEP, w.DARK, w.LAMP = SOLID, WATER, HURT, DEEP, DARK, LAMP
local T = { path = 42, door = 51, door_open = 52, lamp_off = 53, lamp_on = 54, stone = 62, mirror = 63,
  switch_off = 104, switch_on = 105, cave_mouth = 123, shrine_gate = 124 }
w.T = T
local MARK = { "start", "slime", "swimmer", "paati", "potter", "villager", "villager2", "piece", "key",
  "pot", "lotus", "heart", "switch_a", "switch_b", "switch_c", "stone_a", "stone_b", "stone_c", "exit",
  "rocks", "event", "irul", "guide", "mirror" }

-- Sprites (cell x + 64 * cell y).
local KAYAL = { down = 552, up = 556, right = 560, left = 560 }
local PEOPLE = { paati = 564, potter = 568, villager = 572, villager2 = 572 }
local ICON = { piece = 944, key = 943, pot = 941, lotus = 942, heart = 938 }

local SPEED, WADE, SLIME_SPEED, SIGHT = 72, 38, 34, 80
local LAMP_R, MM_R, FLARE_TIME, FLARE_R = 40, 32, 0.45, 84
local AHEAD = { down = { 0, 9 }, up = { 0, -9 }, left = { -9, 0 }, right = { 9, 0 } }
local DIRS = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }

w.ticks = 0
w.p = { x = 0, y = 0, w = 8, h = 6, face = "down", step = 0 }
w.mm = { x = 0, y = 0, t = 0 }
w.cam = { x = 0, y = 0 }
w.npcs, w.slimes, w.things, w.actors, w.lamps, w.marks = {}, {}, {}, {}, {}, {}
w.beams, w.sources = {}, {}             -- segments of light (x0, y0, x1, y1, ...), and where they start
w.caves = ""                            -- the insides of caves (see w.start)
local exits, groups, stones, said = {}, {}, {}, {}
local drawn, slots = {}, {}
local shake_t, shake_px, locked_wait = 0, 0, 0

function w.say(who, key, ...) talk.say(story.name(who), story.t(key, ...)) end

-- Say something once a region: Minmini's tips.
function w.tip(key, who)
  if not said[key] then said[key] = true; w.say(who or "minmini", key) end
end

function w.shake(px, t) shake_px, shake_t = px, t end
function w.flags_at(x, y) return map.flags(map.get(0, x // 8, y // 8)) end
function w.center() return w.p.x + 4, w.p.y + 3 end
function w.near(a, b, d) local dx, dy = a.x - b.x, a.y - b.y return dx * dx + dy * dy <= d * d end
function w.light(x, y, r) dark.light(x - w.cam.x, y - w.cam.y, r) end

function w.add_slime(x, y, swim)
  local s = { x = x - 4, y = y - 3, w = 8, h = 6, home_x = x, home_y = y, dx = 0, dy = 0,
              think = 0, shrunk = 0, swim = swim, wob = math.random() * 2 }
  w.slimes[#w.slimes + 1] = s
  return s
end

-- The lit lamp whose light the point (x, y) is in, if any.
function w.lamp_over(x, y)
  for _, l in ipairs(w.lamps) do
    local dx, dy = x - l.x, y - l.y
    if l.lit and dx * dx + dy * dy < (LAMP_R + 6) ^ 2 then return l end
  end
end

function w.lit_count(from_y)
  local n, all = 0, 0
  for _, l in ipairs(w.lamps) do
    if l.cy >= (from_y or 0) then all = all + 1; if l.lit then n = n + 1 end end
  end
  return n, all
end

function w.light_lamp(l, quiet)
  if l.lit then return end
  l.lit = true
  if not l.src then map.set(0, l.cx, l.cy, T.lamp_on) end
  fx.burst(l.x, l.y - 4, 16, fx.SPARK)
  if not quiet then
    progress.sfx(7)   -- lamp
    w.checkpoint.x, w.checkpoint.y = w.p.x, w.p.y
  end
  if w.region.event then w.region.event(w, "lit", l) end
  if l.src then w.trace() end                 -- a beam lamp, lit: its beam starts
end

-- ---- loading a region ------------------------------------------------------------

function w.start(chapter, region)
  w.chapter, w.region = chapter, region
  for _, t in ipairs({ w.npcs, w.slimes, w.things, w.actors, w.lamps, w.beams, w.sources }) do
    for i = #t, 1, -1 do t[i] = nil end
  end
  for _, t in ipairs({ w.marks, exits, groups, stones, said }) do
    for k in pairs(t) do t[k] = nil end
  end
  talk.clear()
  fx.clear()
  script.cancel()                     -- nothing from a game that ended carries on
  w.dead = false
  map.load(region.map)
  local tw, th = map.size()
  w.map_w, w.map_h = tw * 8, th * 8
  -- markers and lamps
  -- the insides of caves, as runs of cells along each row: drawn black
  -- while Kayal is out in the light, so what is in a cave cannot be seen
  -- from outside it. The mouths stay visible. Kept as a string, three bytes
  -- a run (cell x, cell y, length), as a table of them would cost kilobytes.
  local caves, run, x0 = {}, 0, 0
  -- A chapter not yet finished starts afresh, whether after being caught or
  -- from the title: what was found in it is put back. A finished one played
  -- again keeps what was found, so nothing counts twice.
  local d = progress.data
  local again = d.unlocked <= chapter
  for cy = 0, th - 1 do
    for cx = 0, tw - 1 do
      local m = map.get(1, cx, cy) - 999
      local kind = MARK[m]
      if kind then
        map.set(1, cx, cy, 0)
        local x, y = cx * 8 + 4, cy * 8 + 4
        -- kept for the regions to read: only the few kinds they ask for, as
        -- a table for each marker costs memory and a lake has hundreds of stones
        local list = w.marks[kind] or {}
        if m == 1 or m >= 20 then
          w.marks[kind] = list
          list[#list + 1] = { x = x, y = y, cx = cx, cy = cy }
        end
        local count = (w.marks["n_" .. kind] or 0) + 1
        w.marks["n_" .. kind] = count
        local id = chapter * 65536 + cy * 256 + cx
        if again and ICON[kind] and d.got[id] then
          d.got[id] = nil
          if kind == "pot" then d.pots = d.pots - 1
          elseif kind == "lotus" then d.lotuses = d.lotuses - 1
          elseif kind == "heart" then d.hearts = d.hearts - 1
          elseif kind == "piece" then d.pieces = d.pieces & ~(1 << ((region.pieces or { 1 })[count] - 1)) end
        end
        if m == 2 or m == 3 then w.add_slime(x, y, m == 3)
        elseif PEOPLE[kind] then
          w.npcs[#w.npcs + 1] = { who = kind, say = kind == "villager2" and "villager" or kind, x = x - 4, y = y - 3, w = 8, h = 6, face = "down",
                                  spr = PEOPLE[kind], alt = kind == "villager2" }
        elseif ICON[kind] and (kind == "key" or not d.got[id]) then
          w.things[#w.things + 1] = { kind = kind, x = x, y = y, id = kind ~= "key" and id, n = count,
                                      bob = math.random() * 6 }
        elseif kind == "exit" then exits[cy * 256 + cx] = true
        elseif m >= 13 and m <= 18 then
          local g = kind:sub(-1)
          if m <= 15 then groups[cy * 256 + cx] = g
          else stones[g] = stones[g] or {}; stones[g][#stones[g] + 1] = cy * 256 + cx end
        end
      end
      local tile, flip_x, flip_y = map.get(0, cx, cy)
      if map.flags(tile) & BEAM ~= 0 then
        -- a beam lamp: lit by hand like any lamp, and only then does it shine
        local l = { cx = cx, cy = cy, x = cx * 8 + 4, y = cy * 8 + 4, lit = false, src = true }
        w.lamps[#w.lamps + 1] = l
        w.sources[#w.sources + 1] = { cx, cy, flip_x and (flip_y and 3 or 1) or (flip_y and 4 or 2), l }
      end
      if map.flags(tile) & LAMP ~= 0 then
        w.lamps[#w.lamps + 1] = { cx = cx, cy = cy, x = cx * 8 + 4, y = cy * 8 + 4, lit = tile == T.lamp_on }
      end
      if not region.dark and map.flags(tile) & DARK ~= 0 and tile ~= T.cave_mouth and run < 255 then
        if run == 0 then x0 = cx end
        run = run + 1
      else
        if run > 0 then caves[#caves + 1] = string.char(x0, cy, run) end
        run = 0
      end
    end
    if run > 0 then caves[#caves + 1] = string.char(x0, cy, run) end
    run = 0
  end
  w.caves = table.concat(caves)
  local s = w.marks.start and w.marks.start[1] or { x = 32, y = 32 }
  local p = w.p
  p.x, p.y, p.face, p.moving, p.pose, p.hide, p.dying = s.x - 4, s.y - 3, "down", false, nil, false, nil
  -- Hearts carry on from the chapter before; a fresh start has them all.
  p.hearts, p.hurt, p.wet = w.carry or progress.data.hearts, 0, 0
  w.carry = nil
  w.checkpoint = { x = p.x, y = p.y }
  w.mm.x, w.mm.y, w.mm.hide = p.x, p.y - 12, false
  w.keys, w.flare, w.flare_cd, w.card_t = 0, 99, 0, 0
  w.fade, w.flash, w.control, w.cam_lock, w.freeze, w.dark = 0, 0, true, nil, false, region.dark
  w.hold, w.still = false, false
  w.cam.x, w.cam.y = s.x - 160, s.y - 120
  w.camera(1)
  if region.music then progress.music(region.music, 800) end
  if region.start then region.start(w) end
  w.trace()
end

function w.card() w.card_t = 3.5 end

-- How many of this region's ruby pieces are still to find.
function w.pieces_left()
  local n = 0
  for _, k in ipairs(w.region.pieces or {}) do
    if progress.data.pieces & (1 << (k - 1)) == 0 then n = n + 1 end
  end
  return n
end

-- ---- harm, and coming back ----------------------------------------------------------

function w.hurt(from_x, from_y)
  local p = w.p
  if p.hurt > 0 or not w.control or w.still then return end
  p.hearts, p.hurt = p.hearts - 1, 1.5
  w.shake(3, 0.25)
  if p.hearts <= 0 then
    w.die()
  else
    progress.sfx(1)   -- hurt
  end
end

-- The dark catches her: she spins, shrinks and is gone in a swirl of dark,
-- the world dims, and the game is over.
-- Once only: whatever caught her may try again while she fades, and the
-- scene's end must not give her back control.
function w.die()
  local p = w.p
  if w.dead then return end
  w.dead, p.hearts = true, 0
  talk.clear()
  progress.sfx(3)   -- lost
  music_stop(300)
  script.run(function(s)
    s.during(1.6, function(dt, k)
      p.dying = k
      if math.random() < 0.7 then fx.burst(p.x + 4, p.y - 2, 1, fx.DARK) end
    end)
    p.hide, p.dying = true, nil
    fx.burst(p.x + 4, p.y - 2, 24, fx.DARK)
    s.fade(0.6, 0.8)
  end, function() w.control = false; core.push("over") end)
end

-- ---- beams of light -----------------------------------------------------------------
-- A beam starts at each lit beam lamp (flags 128) and goes down, or the way
-- its flips say: right for flip x, up for flip y, left for both. A mirror
-- turns it: "/" as drawn, "\" when flipped. It lights the lamp it reaches
-- and stops at anything solid. A lamp only a beam can light (l.beam) stays
-- lit while a beam reaches it, and goes out when none does.
local reached = {}
function w.trace()
  local b = w.beams
  for i = #b, 1, -1 do b[i] = nil end
  for k in pairs(reached) do reached[k] = nil end
  for _, src in ipairs(w.sources) do
    if not src[4].lit then goto next end
    local cx, cy = src[1], src[2]
    local d = src[3]
    local x0, y0 = cx * 8 + 4, cy * 8 + 4
    for _ = 1, 160 do
      cx, cy = cx + DIRS[d][1], cy + DIRS[d][2]
      local tile, flip = map.get(0, cx, cy)
      local f = map.flags(tile)
      if f & MIRROR ~= 0 then
        b[#b + 1], b[#b + 2], b[#b + 3], b[#b + 4] = x0, y0, cx * 8 + 4, cy * 8 + 4
        x0, y0 = cx * 8 + 4, cy * 8 + 4
        -- "/" sends right to up, down to left; "\" right to down, down to right
        if flip then d = ({ 2, 1, 4, 3 })[d] else d = ({ 4, 3, 2, 1 })[d] end
      elseif f & SOLID ~= 0 or tile == 0 then
        local l = f & LAMP ~= 0 and w.lamp_at(cx, cy)
        if l then
          reached[l] = true
          if not l.lit then
            w.light_lamp(l, true)
            progress.sfx(26)   -- chime
          end
        end
        b[#b + 1], b[#b + 2], b[#b + 3], b[#b + 4] = x0, y0, cx * 8 + 4 - DIRS[d][1] * 4, cy * 8 + 4 - DIRS[d][2] * 4
        break
      end
    end
    ::next::
  end
  for _, l in ipairs(w.lamps) do
    if l.beam and l.lit and not reached[l] then
      l.lit = false
      map.set(0, l.cx, l.cy, T.lamp_off)
      progress.sfx(16)   -- blip: the light has left it
    end
  end
end

function w.lamp_at(cx, cy)
  for _, l in ipairs(w.lamps) do
    if l.cx == cx and l.cy == cy then return l end
  end
end

-- ---- Kayal: walking, and what A, B and X do ------------------------------------------

local function gate(cx, cy, tile)
  if tile ~= T.shrine_gate then return end
  if w.keys <= 0 then
    if locked_wait <= 0 then locked_wait = 3; w.say("minmini", "locked") end
    return
  end
  w.keys = w.keys - 1
  map.set(0, cx, cy, T.path)
  for _, d in ipairs(DIRS) do         -- a gate as wide as its path opens whole
    for k = 1, 4 do
      if map.get(0, cx + d[1] * k, cy + d[2] * k) ~= tile then break end
      map.set(0, cx + d[1] * k, cy + d[2] * k, T.path)
    end
  end
  fx.burst(cx * 8 + 4, cy * 8 + 4, 12, fx.DUST)
  progress.sfx(8)   -- door
end

local function control(dt)
  local p, r = w.p, w.region
  if core.pressed("start") then core.push("pause") return end
  local dx, dy = 0, 0
  if btn("left") then dx = -1 elseif btn("right") then dx = 1 end
  if btn("up") then dy = -1 elseif btn("down") then dy = 1 end
  if dx ~= 0 and dy ~= 0 then dx, dy = dx * 0.75, dy * 0.75 end
  if dy ~= 0 then p.face = dy < 0 and "up" or "down" end
  if dx ~= 0 then p.face = dx < 0 and "left" or "right" end
  p.moving = dx ~= 0 or dy ~= 0
  local cx, cy = w.center()
  if w.flags_at(cx, cy + 2) & WATER ~= 0 then p.wet = 0.6 else p.wet = math.max(0, p.wet - dt) end
  local speed = p.wet > 0 and WADE or SPEED
  local ox, oy = p.x, p.y
  move.solid = SOLID | DEEP
  local hx, hy = move.by(p, dx * speed * dt, dy * speed * dt)
  for _, n in ipairs(w.npcs) do
    if move.overlap(p, n) then p.x, p.y = ox, oy break end
  end
  cx, cy = w.center()
  local a = AHEAD[p.face]
  local tx, ty = cx + a[1], cy + a[2]
  if hx or hy then gate(tx // 8, ty // 8, map.get(0, tx // 8, ty // 8)) end
  if w.flags_at(cx, cy) & HURT ~= 0 then w.hurt(tx, ty) end

  local ccx, ccy = cx // 8, (cy + 2) // 8
  if map.get(0, ccx, ccy) == T.switch_off then     -- a switch raises the stones of its group
    map.set(0, ccx, ccy, T.switch_on)
    progress.sfx(10)   -- switch
    local g = groups[ccy * 256 + ccx]
    for _, at in ipairs(g and stones[g] or {}) do
      map.set(0, at % 256, at // 256, T.stone)
      fx.burst(at % 256 * 8 + 4, at // 256 * 8 + 4, 3, fx.SPLASH)
    end
    progress.sfx(11)   -- stone
    if r.event then r.event(w, "switch", g) end
  end
  if exits[ccy * 256 + ccx] then
    if r.exit then r.exit(w)
    elseif w.pieces_left() == 0 then w.finish()
    else
      p.x, p.y = ox, oy                             -- not yet: Minmini says what is missing
      if locked_wait <= 0 then locked_wait = 3; w.say("minmini", r.lines.exit) end
    end
  end
  for i = #w.things, 1, -1 do
    local t = w.things[i]
    if math.abs(t.x - cx) < 8 and math.abs(t.y - cy) < 8 then
      table.remove(w.things, i)
      w.pick(t)
    end
  end

  if core.pressed("a") then
    -- talk to whoever is in front, or light the lamp, turn the mirror, open the gate
    for _, n in ipairs(w.npcs) do
      if math.abs(n.x + 4 - tx) < 12 and math.abs(n.y + 3 - ty) < 12 then
        n.face = cx < n.x + 4 and "left" or "right"
        if r.talk then r.talk(w, n) else w.say(n.say, r.lines[n.who]) end
        return
      end
    end
    local tcx, tcy = tx // 8, ty // 8
    local tile, flip = map.get(0, tcx, tcy)
    local f = map.flags(tile)
    if f & (LAMP | BEAM) ~= 0 and not r.no_hand_lamps then
      local l = w.lamp_at(tcx, tcy)
      if l and not l.beam then w.light_lamp(l) end
    elseif f & MIRROR ~= 0 then
      map.set(0, tcx, tcy, tile, not flip)
      progress.sfx(15)   -- mirror
      w.trace()
    elseif tile == T.shrine_gate then gate(tcx, tcy, tile)
    elseif r.use then r.use(w, tcx, tcy, tile) end
  elseif core.pressed("b") and w.flare_cd <= 0 and not w.no_flare then
    w.flare, w.flare_cd = 0, progress.data.lamp and 2 or 3
    progress.sfx(6)   -- flare
    fx.burst(w.mm.x, w.mm.y, 30, fx.GLOW)
    for _, s in ipairs(w.slimes) do
      if w.near(s, p, FLARE_R) then s.shrunk = 5 end
    end
    if r.event then r.event(w, "flare") end
  elseif core.pressed("x") then
    w.say("minmini", r.hint and r.hint(w) or r.lines and (w.pieces_left() > 0 and r.lines.hint or r.lines.done) or "no_hint")
  end
end

-- Something picked up: count it, keep it in the save, and say so.
function w.pick(t)
  local d, k = progress.data, t.kind
  if t.id then d.got[t.id] = true end
  fx.burst(t.x, t.y, 14, k == "piece" and fx.RUBY or fx.SPARK)
  -- the sparkle scares off slimes close by, so none is on her when the
  -- world moves again
  for _, s in ipairs(w.slimes) do
    if w.near(s, w.p, 40) then s.shrunk = 2 end
  end
  if k == "key" then w.keys = w.keys + 1
  elseif k == "pot" then d.pots = d.pots + 1
  elseif k == "lotus" then d.lotuses = d.lotuses + 1
  elseif k == "heart" then d.hearts = math.min(7, d.hearts + 1); w.p.hearts = d.hearts end
  if k == "piece" then
    d.pieces = d.pieces | (1 << ((w.region.pieces or { 1 })[t.n] - 1))
    -- Kayal holds the piece up, and it joins the ring of seven
    w.hold = true                                      -- everything hostile waits
    script.run(function(s)
      music_stop(200)
      progress.sfx(2)   -- piece
      w.p.pose = 808
      w.held = { x = w.p.x + 4, y = w.p.y - 14 }
      s.during(1.6, function() if math.random() < 0.5 then fx.burst(w.held.x, w.held.y, 1, fx.RUBY) end end)
      w.held, w.p.pose = nil, nil
      s.say("minmini", "got_piece", progress.piece_count())
      w.hold = false
      if w.region.music then progress.music(w.region.music, 600) end
      if w.region.event then w.region.event(w, "got", t) end
    end, progress.checkpoint)
    return
  end
  progress.sfx(k == "heart" and 25 or k == "key" and 9 or 0)
  w.say("minmini", k == "lotus" and d.lotuses >= 7 and "got_lotuses" or "got_" .. k, d.lotuses)
  progress.save()
  if w.region.event then w.region.event(w, "got", t) end
end

-- ---- slimes ---------------------------------------------------------------------------

local function sign(v) return v > 0.5 and 1 or v < -0.5 and -1 or 0 end

local function slimes(dt)
  local px, py = w.center()
  local c = w.cam
  local kayal_safe = w.lamp_over(px, py)
  for _, s in ipairs(w.slimes) do
    -- only those near the screen move; the rest wait
    if s.x > c.x - 96 and s.x < c.x + 416 and s.y > c.y - 96 and s.y < c.y + 336 then
      local sx, sy = s.x + 4, s.y + 3
      local speed, l = 22, w.lamp_over(sx, sy)
      if s.shrunk > 0 then                          -- shrunk by a flare: away from her
        s.shrunk = s.shrunk - dt
        s.dx, s.dy, speed = sign(sx - px), sign(sy - py), 24
      elseif l then                                 -- in lamplight: out of it
        s.dx, s.dy, speed = sign(sx - l.x), sign(sy - l.y), 46
        if s.dx == 0 and s.dy == 0 then s.dx = 1 end
      elseif math.abs(px - sx) < SIGHT and math.abs(py - sy) < SIGHT and not kayal_safe then
        -- straight at her; a wall in the way is slid along, and a slime that
        -- is stuck tries the other way round for a moment
        speed = SLIME_SPEED
        if s.think > 0 then s.think = s.think - dt
        else s.dx, s.dy = sign(px - sx), sign(py - sy) end
      else                                          -- wander, not far from home
        s.think = s.think - dt
        if s.think <= 0 then
          local way = math.random(6)
          s.dx = way == 1 and -1 or way == 2 and 1 or 0
          s.dy = way == 3 and -1 or way == 4 and 1 or 0
          if math.abs(sx - s.home_x) > 64 or math.abs(sy - s.home_y) > 64 then
            s.dx, s.dy = sign(s.home_x - sx), sign(s.home_y - sy)
          end
          s.think = 0.6 + math.random() * 1.4
        end
      end
      local ox, oy = s.x, s.y
      move.solid = s.swim and SOLID or SOLID | DEEP
      local hx, hy = move.by(s, s.dx * speed * dt, s.dy * speed * dt)
      if (hx or hy) and s.think <= 0 then
        if hx then s.dx, s.dy = 0, s.dy ~= 0 and s.dy or (math.random() < 0.5 and -1 or 1)
        else s.dx, s.dy = s.dx ~= 0 and s.dx or (math.random() < 0.5 and -1 or 1), 0 end
        s.think = 0.5
      end
      if s.swim and w.flags_at(s.x + 4, s.y + 3) & (WATER | DEEP) == 0 then s.x, s.y, s.think = ox, oy, 0
      elseif not s.swim and s.shrunk <= 0 and not l and w.lamp_over(s.x + 4, s.y + 3) then s.x, s.y = ox, oy end
      if s.shrunk <= 0 and move.overlap(w.p, s) then w.hurt(s.x + 4, s.y + 3) end
    end
  end
end

-- ---- each frame -----------------------------------------------------------------------

function w.camera(dt)
  local tx, ty
  if w.cam_lock then tx, ty = w.cam_lock.x, w.cam_lock.y else tx, ty = w.center() end
  local k, c = math.min(1, dt * 7), w.cam
  c.x = math.max(0, math.min(c.x + (tx - 160 - c.x) * k, w.map_w - 320))
  c.y = math.max(-16, math.min(c.y + (ty - 120 - c.y) * k, w.map_h - 240))   -- room for the top bar
  if w.map_w < 320 then c.x = (w.map_w - 320) / 2 end
  local fh = w.region.floor_h                     -- a map of floors stacked: show one at a time
  if fh then
    local top = (w.p.y // fh) * fh
    c.y = math.max(top - 16, math.min(c.y, top + fh - 240))
  end
end

function w.update(dt)
  local p = w.p
  w.ticks = w.ticks + 1
  fx.update(dt)
  shake_t, locked_wait, w.card_t = shake_t - dt, locked_wait - dt, w.card_t - dt
  w.flash = math.max(0, w.flash - dt * 3)
  w.flare, w.flare_cd, p.hurt = w.flare + dt, w.flare_cd - dt, p.hurt - dt
  local talking = talk.update(dt)
  if script.active() then script.update(dt)
  elseif not talking and w.control then control(dt) end
  -- While Kayal holds up a piece, and while anyone talks, nothing hostile
  -- moves or hurts: slimes, falling rocks and Irul's orbs all wait. Worked
  -- out after she moves, so a piece picked up this frame counts at once.
  w.still = talking or w.freeze or w.hold
  p.step = p.moving and p.step + dt or 0
  -- Minmini drifts after Kayal and keeps to the same place whichever way
  -- she faces: just above her right shoulder as she faces us (our left),
  -- clear of her face
  local mm = w.mm
  local k = math.min(1, dt * 12)            -- close behind, so she never trails across Kayal
  mm.t = mm.t + dt
  mm.x, mm.y = mm.x + (p.x - 8 - mm.x) * k, mm.y + (p.y - 12 - mm.y) * k
  if not w.still then slimes(dt) end
  if w.region.update then w.region.update(w, dt) end
  w.camera(dt)
end

-- ---- drawing --------------------------------------------------------------------------

local function by_feet(a, b) return a[1] < b[1] end

-- cos and sin of 24 angles a turn, one after the other, for the lamps' glow
local RING = {}
for k = 0, 23 do RING[2 * k + 1], RING[2 * k + 2] = math.cos(k * 0.2618), math.sin(k * 0.2618) end

local function add(kind, a, y)
  local n = #drawn + 1
  local s = slots[n] or {}
  slots[n], drawn[n] = s, s
  s[1], s[2], s[3] = y, kind, a
end

function w.draw_world()
  local c, p, f = w.cam, w.p, w.ticks     -- the world's own clock: it stands still while paused
  local ox, oy = 0, 0
  if shake_t > 0 then ox, oy = math.random(-shake_px, shake_px), math.random(-shake_px, shake_px) end
  camera(c.x + ox, c.y + oy)
  if w.region.night then for i = 1, 31 do pal(i, i + 32) end end   -- the shadow ramp: every colour darker
  map.draw(0)
  pal()
  if w.region.draw then w.region.draw(w) end

  for i = #drawn, 1, -1 do drawn[i] = nil end
  add(1, p, p.y + p.h)
  for _, n in ipairs(w.npcs) do add(2, n, n.y + n.h) end
  -- outside, in the light: what is in a cave is not seen, slimes included
  local outside = #w.caves > 0 and w.flags_at(p.x + 4, p.y + 3) & DARK == 0
  for _, s in ipairs(w.slimes) do
    if s.x > c.x - 24 and s.x < c.x + 336 and s.y > c.y - 8 and s.y < c.y + 256
        and not (outside and w.flags_at(s.x + 4, s.y + 3) & DARK ~= 0) then add(3, s, s.y + s.h) end
  end
  for _, t in ipairs(w.things) do add(4, t, t.y + 3) end
  for _, a in ipairs(w.actors) do add(5, a, a.y) end
  for _, l in ipairs(w.lamps) do
    if l.x > c.x - 8 and l.x < c.x + 328 and l.y > c.y and l.y < c.y + 264 then add(6, l, l.y + 4) end
  end
  table.sort(drawn, by_feet)
  for _, d in ipairs(drawn) do
    local kind, a = d[2], d[3]
    if kind == 1 and a.dying then                   -- Kayal caught: spinning, shrinking
      local n = KAYAL[({ "down", "right", "up", "left" })[a.dying * 16 // 1 % 4 + 1]]
      local size = 16 * (1 - a.dying)
      if a.dying * 16 // 1 % 4 == 3 then size = -size end                -- facing left: drawn flipped
      sspr(n % 64 * 8, n // 64 * 8, 16, 16, a.x + 4 - math.abs(size) / 2, a.y + 6 - math.abs(size), size, math.abs(size))
    elseif kind == 1 then                           -- Kayal, blinking just after a hit
      if not a.hide and not (a.hurt > 0 and a.hurt * 10 % 2 < 1 and w.control) then
        spr(a.pose or KAYAL[a.face] + (a.moving and a.step * 8 % 2 < 1 and 2 or 0), a.x - 4, a.y - 10, 2, 2,
            a.face == "left" and not a.pose)
      end
    elseif kind == 2 then                           -- people; the second villager in other clothes
      if a.alt then pal(14, 12) pal(3, 28) end
      spr(a.spr + (a.moving and f // 8 % 2 * 2 or 0), a.x - 4, a.y - 10, 2, 2, a.face == "left")
      pal()
    elseif kind == 3 then
      spr(a.shrunk > 0 and 690 or (f * 0.07 + a.wob) % 2 < 1 and 686 or 688, a.x - 4, a.y - 10, 2, 2)
    elseif kind == 4 then
      spr(948, a.x - 4, a.y - 3)
      spr(ICON[a.kind], a.x - 4, a.y - 4 + math.sin(a.bob + f / 15) * 1.5)
    elseif kind == 6 then                           -- a lamp post on its stone slab
      if a.lit then
        local fl = (f // 6 + a.cx) % 3
        -- a soft glow: two rings of dots, turning and flickering
        local r = 5 + (f // 8 + a.cy) % 2
        local turn = f // 13                           -- a step of the ring every 13 frames
        for i = 0, 11 do
          local k = (i * 2 + turn) % 24 * 2
          pset(a.x + RING[k + 1] * r, a.y - 15 + RING[k + 2] * r * 0.8, i % 2 == 0 and 9 or 41)
          if i % 3 == 0 then
            k = (-i * 2 - turn) % 24 * 2                 -- the outer ring turns the other way
            pset(a.x + RING[k + 1] * (r + 3), a.y - 15 + RING[k + 2] * (r + 2), 10)
          end
        end
        spr(814 + fl, a.x - 4, a.y - 17, 1, 2)
        if (f + a.cx * 7) % 53 == 0 then fx.burst(a.x, a.y - 18, 1, fx.GLOW) end
      else
        spr(817, a.x - 4, a.y - 17, 1, 2)
      end
    elseif not a.hide then
      if a.draw then a:draw() else spr(a.spr + (a.moving and f // 8 % 2 * 2 or 0), a.x - 8, a.y - 16, 2, 2, a.face == "left") end
    end
  end
  w.sprites = #drawn
  if w.held then spr(944, w.held.x - 4, w.held.y - 4 + math.sin(f / 6)) end
  if w.region.night then for i = 1, 31 do pal(i, i + 32) end end
  map.draw(1)
  pal()
  local b = w.beams
  for i = 1, #b, 4 do
    line(b[i], b[i + 1], b[i + 2], b[i + 3], f % 4 < 2 and 10 or 7)
    line(b[i] + 1, b[i + 1], b[i + 2] + 1, b[i + 3], 23)
  end
  if w.region.draw_top then w.region.draw_top(w) end
  if outside then
    local cv = w.caves
    for i = 1, #cv, 3 do
      local x, y, len = cv:byte(i, i + 2)
      if y * 8 > c.y - 8 and y * 8 < c.y + 240 then rectfill(x * 8, y * 8, len * 8, 8, 32) end
    end
  end
  fx.draw()
  local mm = w.mm
  if not mm.hide then
    local bob = math.sin(mm.t * 5) * 2
    circ(mm.x, mm.y + bob, 3 + f // 6 % 2, 10)
    spr(936 + f // 5 % 2, mm.x - 4, mm.y - 4 + bob)
  end
  camera()

  -- Night: black but for the lights.
  local k = w.flare < FLARE_TIME and math.sin(w.flare / FLARE_TIME * 3.1416) or 0
  if w.dark or w.flags_at(p.x + 4, p.y + 3) & DARK ~= 0 then
    dark.clear()
    w.light(mm.x, mm.y, MM_R + (progress.data.lamp and 16 or 0) + f // 8 % 2 + FLARE_R * k)
    for _, l in ipairs(w.lamps) do
      if l.lit then w.light(l.x, l.y, LAMP_R + (f // 10 + l.cx) % 3) end
    end
    for _, t in ipairs(w.things) do w.light(t.x, t.y, 10) end
    for i = 1, #b, 4 do w.light(b[i + 2], b[i + 3], 12) end
    if w.region.lights then w.region.lights(w) end
    dark.draw()
  elseif k > 0 then
    circ(mm.x - c.x, mm.y - c.y, FLARE_R * k, 10)
  end
end

script.attach(w)
return w
