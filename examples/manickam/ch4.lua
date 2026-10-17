-- ch4.lua — chapter 4, Mullu Malai: the thorny hills. Thorns hurt; in the
-- canyon, rocks fall where their shadows grow, most of them aimed at her:
-- where she stands, or where she is heading; the two pieces lie in dark
-- caves. Taking the second, Irul brings the cave down, and Kayal has a
-- minute to get out by the cave's far mouth, with rocks falling all round.

local progress = require("progress")
local script   = require("script")
local talk     = require("talk")
local story    = require("story")
local fx       = require("fx")

local region = { map = "hills.ooru", music = 5, pieces = { 5, 6 },   -- hills music
  lines = { villager = "c4_hermit", hint = "c4_exit", exit = "c4_exit" } }
local ESCAPE = 60
local rx, ry, rt = {}, {}, {}           -- falling rocks: where, and how long until they land
local n, clock, aim
local FALL = 1.1                         -- seconds from the shadow to the crash
local AHEAD = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

function region.start(w)
  w.npcs[1].say = "hermit"
  n, clock, aim, region.escape = 0, 0, 0, nil
  w.card()
  w.tip("c4_start")
end

function region.update(w, dt)
  if w.still then return end                         -- rocks wait while she picks up or talks
  local p = w.p
  local px, py = p.x + 4, p.y + 3
  -- rocks fall near Kayal in the canyon, and everywhere while she escapes
  local due = region.escape and 0.3
  for _, m in ipairs(w.marks.rocks) do
    if not due and math.abs(px - m.x) < 48 and math.abs(py - m.y) < 40 then due = 0.6; w.tip("c4_rocks") end
  end
  clock = clock + dt
  if due and clock > due and n < 24 and w.control then
    clock, n, aim = 0, n + 1, aim % 3 + 1
    -- in turn: on her, on her way (where she will be when it lands, if she
    -- keeps walking), and anywhere near; so standing still is no shelter
    local x, y
    if aim == 1 then
      x, y = px + math.random(-4, 4), py + math.random(-3, 3)
    elseif aim == 2 then
      local d = p.moving and AHEAD[p.face] or { 0, 0 }
      x, y = px + d[1] * 60 * FALL + math.random(-6, 6), py + d[2] * 60 * FALL + math.random(-6, 6)
    else
      x, y = px + math.random(-48, 48), py + math.random(-36, 36)
    end
    rx[n], ry[n], rt[n] = x, y, FALL
  end
  local i = 1
  while i <= n do
    rt[i] = rt[i] - dt
    if rt[i] <= 0 then
      fx.burst(rx[i], ry[i], 10, fx.DUST)
      progress.sfx(14)   -- crash
      w.shake(1, 0.1)
      if math.abs(px - rx[i]) < 10 and math.abs(py - ry[i]) < 8 then w.hurt(rx[i], ry[i]) end
      rx[i], ry[i], rt[i] = rx[n], ry[n], rt[n]
      n = n - 1
    else
      i = i + 1
    end
  end
  if w.flags_at(px, py) & w.DARK ~= 0 then w.tip("c4_cave") end
  if region.escape and w.control then
    region.escape = region.escape - dt
    if region.escape <= 0 then
      region.escape = 0
      w.say("minmini", "c4_late")
      w.die()
    end
  end
end

-- The second piece: Irul brings the cave down. Inside the piece's cut-scene.
function region.event(w, what, t)
  if what == "got" and t.kind == "piece" and w.pieces_left() == 0 then
    w.checkpoint.x, w.checkpoint.y = w.p.x, w.p.y
    w.shake(3, 2)
    progress.sfx(27)   -- rumble
    script.say("irul", "c4_irul1")
    script.say("minmini", "c4_irul2")
    region.escape = ESCAPE
    progress.music(7, 300)   -- irul music
  end
end

function region.exit(w)
  if not region.escape then
    if w.pieces_left() > 0 then w.p.x = w.p.x - 8; w.say("minmini", "c4_exit") end
    return
  end
  region.escape = nil
  w.control = false
  talk.say(story.name("minmini"), story.t("c4_safe"), w.finish)
end

function region.draw(w)
  for i = 1, n do                        -- shadows grow as the rocks come down
    local r = (FALL - rt[i]) * 6
    rectfill(rx[i] - r, ry[i] - r / 3, r * 2, r / 1.5, 32)
  end
end

function region.draw_top(w)
  for i = 1, n do spr(810, rx[i] - 8, ry[i] - 12 - rt[i] * 150, 2, 2) end
end

function region.hud(w)
  if region.escape then
    local s = math.ceil(region.escape)
    print(string.format("%d:%02d", s // 60, s % 60), 222, 3, s <= 10 and 8 or 7)
  end
end

return region
