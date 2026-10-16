-- bench.lua — the benchmark: a fixed run through the game's heaviest kinds
-- of scene, reporting how the machine coped, for testing a board at bring-up.
--
-- Switch it on with SELECT on the title screen, then start a game. R on the
-- title, while it is on, turns up the stress: x1, x2, x4, past the spec's
-- budgets, to find where a board breaks. Each stage runs for STAGE_FRAMES
-- frames with no input needed, and at its end one line goes to dbg(): the
-- terminal on a desktop, USB serial on a board:
--
--   bench <stage> frames=<n> cpu_avg=<%> cpu_max=<%> fps_min=<n> mem_peak=<KB>
--
-- The stages: 128 sprites over a full screen of tiles; sparks; night, a
-- screen of darkness cut by moving lights; Irul, three serpents and a storm
-- of orbs; the biggest map there is, both layers, scrolling; Tamil text;
-- and sound, every channel busy over the music.
--
-- cpu and fps need a clock, which a port may not have; they read "n/a" then.
-- The random numbers are seeded the same way every time, so every machine
-- runs exactly the same frames and the numbers can be compared.
--
-- Adds the scene "bench".

local core     = require("core")
local story    = require("story")
local progress = require("progress")
local fx       = require("fx")
local dark     = require("dark")
local irul     = require("irul")

local STAGE_FRAMES = 600              -- ten seconds a stage
local LINE = "வணக்கம்! காட்டில் மாணிக்கங்கள் ஒளிந்திருக்கின்றன. "
local NAMES = { "sprites", "sparks", "night", "irul", "map", "text", "sound" }

local stage, frame, results, k
local ax, ay, adx, ady = {}, {}, {}, {}      -- things moving about the screen
local snakes

-- How many moving things each stage has, at stress x1.
local COUNT = { 128, 0, 24, 100, 0, 0, 8 }

local function bounce(n, dt)
  for i = 1, n do
    ax[i], ay[i] = ax[i] + adx[i] * dt, ay[i] + ady[i] * dt
    if ax[i] < 0 or ax[i] > 304 then adx[i] = -adx[i] end
    if ay[i] < 0 or ay[i] > 224 then ady[i] = -ady[i] end
  end
end

local function begin(n)
  stage, frame = n, 0
  results[n] = { frames = 0, cpu_sum = 0, cpu_n = 0, mem_peak = 0 }
  local count = COUNT[n] * k
  for i = 1, math.max(count, #ax) do
    if i <= count then
      ax[i], ay[i], adx[i], ady[i] = math.random(0, 304), math.random(0, 224), math.random(-60, 60), math.random(-60, 60)
    else
      ax[i], ay[i], adx[i], ady[i] = nil, nil, nil, nil
    end
  end
  if n == 2 then fx.reserve(128 * k) end
  if n == 3 then fx.release() map.load("vayal.ooru") end
  if n == 4 then snakes = { irul.new(16, 4, 60, 60), irul.new(16, 4, 160, 120), irul.new(16, 4, 260, 180) } end
  if n == 5 then snakes = nil end
  if n == 7 then progress.music(8, 0) end   -- festival music
end

local function update(dt)
  local n, f, count = stage, frame, COUNT[stage] * k
  if n == 1 or n == 3 then bounce(count, dt)
  elseif n == 2 then
    for _ = 1, 4 * k do fx.burst(math.random(20, 300), math.random(40, 200), 8, fx.SPARK) end
    fx.update(dt)
  elseif n == 4 then
    for i, s in ipairs(snakes) do s:go(160 + math.cos(f / 40 + i * 2) * 120, 120 + math.sin(f / 30 + i) * 90) end
    for i = 1, count do                   -- orbs fly out and come back round
      if f % 120 == i % 120 or not ax[i] then ax[i], ay[i] = snakes[i % 3 + 1].x, snakes[i % 3 + 1].y end
      local a = i * 0.7 + f / 90
      ax[i], ay[i] = ax[i] + math.cos(a) * 60 * dt, ay[i] + math.sin(a) * 60 * dt
    end
  elseif n == 7 and f % 8 == 0 then
    for c = 0, 7 do progress.sfx(c * 3 % 30, c) end
  end
end

local function draw()
  local n, f, count = stage, frame, COUNT[stage] * k
  if n == 1 then
    for cy = 0, 29 do for cx = 0, 39 do spr(40 + (cx + cy) % 2, cx * 8, cy * 8) end end
    for i = 1, count do spr((i % 2 == 0 and 552 or 686) + f // 8 % 2 * 2, ax[i], ay[i], 2, 2) end
  elseif n == 2 then
    cls(1)
    fx.draw()
  elseif n == 3 then
    camera(f % 700, f % 400) map.draw(0) map.draw(1) camera()
    dark.clear()
    for i = 1, count do dark.light(ax[i], ay[i], 20 + i % 3 * 10) end
    dark.draw()
  elseif n == 4 then
    cls(13)
    for _, s in ipairs(snakes) do s:draw() end
    for i = 1, count do spr(946, ax[i], ay[i]) end
  elseif n == 5 then
    camera(f * 1.4 % 704, f * 0.9 % 784) map.draw(0) map.draw(1) camera()
  elseif n == 6 then
    cls(1)
    for row = 0, 9 do print(LINE, -((f + row * 37) % 200), row * 24, 7 + row % 4) end
  else
    cls(17)
    for c = 0, 7 do rectfill(20 + c * 36, 120 - (f + c * 5) % 40, 28, 40, 8 + c) end
  end
end

core.add("bench", {
  enter = function()
    math.randomseed(1)                -- the same frames on every machine
    k = progress.stress or 1
    results = {}
    dbg("bench start stress=" .. k)
    begin(1)
  end,
  update = function(dt)
    if stage > #NAMES then
      if core.pressed("a") or core.pressed("start") then
        ax, ay, adx, ady, snakes = {}, {}, {}, {}, nil   -- give the memory back
        fx.release()
        music_stop()
        collectgarbage()
        core.go("title")
      end
      return
    end
    local r = results[stage]
    update(dt)
    frame, r.frames = frame + 1, r.frames + 1
    local cpu, fps = stat("cpu"), stat("fps")
    if cpu then r.cpu_sum, r.cpu_n = r.cpu_sum + cpu, r.cpu_n + 1; r.cpu_max = math.max(r.cpu_max or 0, cpu) end
    if fps and frame > 60 then r.fps_min = math.min(r.fps_min or fps, fps) end
    r.mem_peak = math.max(r.mem_peak, math.ceil(stat("mem")))
    if frame >= STAGE_FRAMES then
      r.cpu_avg = r.cpu_n > 0 and r.cpu_sum // r.cpu_n or nil
      r.line = string.format("bench %s frames=%d cpu_avg=%s cpu_max=%s fps_min=%s mem_peak=%d",
        NAMES[stage], r.frames, r.cpu_avg or "n/a", r.cpu_max or "n/a", r.fps_min or "n/a", r.mem_peak)
      dbg(r.line)
      if stage < #NAMES then begin(stage + 1) else stage = #NAMES + 1; music_stop(); dbg("bench done") end
    end
  end,
  draw = function()
    if stage <= #NAMES then
      draw()
      rectfill(0, 0, 320, 10, 32)
      print(string.format("%s %d/%d %s x%d", story.t("bench_title"), stage, #NAMES, NAMES[stage], k), 2, 1, 8)
      return
    end
    cls(1)
    core.center(story.t("bench_done") .. " x" .. k, 16, 10)
    print("        cpu avg/max  fps  mem", 8, 40, 6)
    for i, r in ipairs(results) do
      print(string.format("%-8s %4s/%-4s %4s %4dK", NAMES[i], r.cpu_avg or "n/a", r.cpu_max or "n/a",
        r.fps_min or "n/a", r.mem_peak), 8, 40 + i * 14, 7)
    end
    core.center(story.t("press_start"), 210, 6)
  end,
})

return { stages = #NAMES, frames = STAGE_FRAMES }
