-- bench.lua — the benchmark: a fixed run through heavy scenes that reports
-- how the machine coped, for testing a board at bring-up.
--
-- Switch it on with SELECT on the title screen, then start a game. Each
-- stage runs for STAGE_FRAMES frames with no input needed, and at its end
-- one line goes to dbg(): the terminal on a desktop, USB serial on a board:
--
--   bench <stage> frames=<n> cpu_avg=<%> cpu_max=<%> fps_min=<n> mem_peak=<KB>
--
-- cpu and fps need a clock, which a port may not have; they read "n/a" then.
-- The random numbers are seeded the same way every time, so every machine
-- runs exactly the same frames and the numbers can be compared.
--
-- Adds the scene "bench".

local core      = require("core")
local story     = require("story")
local progress  = require("progress")

local STAGE_FRAMES = 600              -- ten seconds a stage
local SPRITES = 128                   -- the sprite budget of SPEC §1, at 16x16
local SPARKS = 400                    -- sparks alive at once in the particle stage
local TILE, KAYAL, SLIME = 40, 552, 686     -- grass; Kayal and a slime, 16x16 (cell x + 64 * cell y)
local SPARK_COLOURS = { 10, 9, 8, 2 }    -- young to old
local LINE = "வணக்கம்! காட்டில் மாணிக்கங்கள் ஒளிந்திருக்கின்றன. "

local stages, stage, frame, results
local actors = {}
-- Sparks for the particle stage, kept as five arrays of numbers rather than
-- a table each: a table per spark would not fit in the Lua memory beside the
-- rest of the game, five arrays easily do.
local sx, sy, svx, svy, sage = {}, {}, {}, {}, {}
local live = 0

local function spark_burst(x, y, n)
  for _ = 1, n do
    if live >= SPARKS then return end
    live = live + 1
    local a, v = math.random() * 6.2832, 20 + math.random() * 60
    sx[live], sy[live], svx[live], svy[live], sage[live] = x, y, math.cos(a) * v, math.sin(a) * v, 0
  end
end

local function sparks_update(dt)
  local i = 1
  while i <= live do
    sage[i] = sage[i] + dt
    if sage[i] >= 1.2 then                    -- burnt out: the last one takes its place
      sx[i], sy[i], svx[i], svy[i], sage[i] = sx[live], sy[live], svx[live], svy[live], sage[live]
      live = live - 1
    else
      svy[i] = svy[i] + 30 * dt
      sx[i], sy[i] = sx[i] + svx[i] * dt, sy[i] + svy[i] * dt
      i = i + 1
    end
  end
end

local function sparks_draw()
  for i = 1, live do pset(sx[i], sy[i], SPARK_COLOURS[math.min(4, sage[i] // 0.3 + 1)]) end
end

local STAGES = {
  { name = "sprites",
    start = function()
      for i = 1, SPRITES do
        actors[i] = { x = math.random(0, 304), y = math.random(0, 224),
                      dx = math.random(-60, 60), dy = math.random(-60, 60),
                      n = i % 2 == 0 and KAYAL or SLIME }
      end
    end,
    update = function(dt)
      for i = 1, SPRITES do
        local a = actors[i]
        a.x, a.y = a.x + a.dx * dt, a.y + a.dy * dt
        if a.x < 0 or a.x > 304 then a.dx = -a.dx end
        if a.y < 0 or a.y > 224 then a.dy = -a.dy end
      end
    end,
    draw = function()
      for cy = 0, 29 do for cx = 0, 39 do spr(TILE + (cx + cy) % 2, cx * 8, cy * 8) end end
      for i = 1, SPRITES do
        local a = actors[i]
        spr(a.n + (frame // 8) % 2 * 2, a.x, a.y, 2, 2)
      end
    end },
  { name = "particles",
    start = function()
      actors = {}                             -- the sprite stage is over: let its memory go
      for i = 1, SPARKS do sx[i], sy[i], svx[i], svy[i], sage[i] = 0, 0, 0, 0, 0 end   -- full size now, so they never grow
      live = 0
    end,
    update = function(dt)
      for _ = 1, 4 do spark_burst(math.random(20, 300), math.random(40, 200), 8) end
      sparks_update(dt)
    end,
    draw = function()
      cls(1)
      sparks_draw()
    end },
  { name = "text",
    start = function() end,
    update = function(dt) end,
    draw = function()
      cls(1)
      for row = 0, 9 do
        print(LINE, -((frame + row * 37) % 200), row * 24, 7 + row % 4)
      end
    end },
}

local function finish_stage()
  local r = results[stage]
  r.cpu_avg = r.cpu_n > 0 and r.cpu_sum // r.cpu_n or nil
  local line = string.format("bench %s frames=%d cpu_avg=%s cpu_max=%s fps_min=%s mem_peak=%d",
    STAGES[stage].name, r.frames, r.cpu_avg or "n/a", r.cpu_max or "n/a", r.fps_min or "n/a", r.mem_peak)
  r.line = line
  dbg(line)
end

local function begin(n)
  stage, frame = n, 0
  results[n] = { frames = 0, cpu_sum = 0, cpu_n = 0, mem_peak = 0 }
  STAGES[n].start()
end

core.add("bench", {
  enter = function()
    math.randomseed(1)                -- the same frames on every machine
    results = {}
    dbg("bench start")
    begin(1)
  end,
  update = function(dt)
    if stage > #STAGES then
      if core.pressed("a") or core.pressed("start") then
        live, actors = 0, {}                  -- give the memory back
        sx, sy, svx, svy, sage = {}, {}, {}, {}, {}
        collectgarbage()
        core.go("title")
      end
      return
    end
    local r = results[stage]
    STAGES[stage].update(dt)
    frame, r.frames = frame + 1, r.frames + 1
    local cpu, fps = stat("cpu"), stat("fps")
    if cpu then r.cpu_sum, r.cpu_n = r.cpu_sum + cpu, r.cpu_n + 1; r.cpu_max = math.max(r.cpu_max or 0, cpu) end
    if fps and frame > 60 then r.fps_min = math.min(r.fps_min or fps, fps) end
    r.mem_peak = math.max(r.mem_peak, math.ceil(stat("mem")))
    if frame >= STAGE_FRAMES then
      finish_stage()
      if stage < #STAGES then begin(stage + 1) else stage = #STAGES + 1; dbg("bench done") end
    end
  end,
  draw = function()
    if stage <= #STAGES then
      STAGES[stage].draw()
      rectfill(0, 0, 320, 10, 32)
      print(story.t("bench_title") .. " " .. stage .. "/" .. #STAGES .. " " .. STAGES[stage].name, 2, 1, 8)
      return
    end
    cls(1)
    core.center(story.t("bench_done"), 20, 10)
    for i, r in ipairs(results) do
      print(STAGES[i].name, 8, 44 + (i - 1) * 40, 10)
      print(string.format("cpu %s/%s%%  fps %s", r.cpu_avg or "n/a", r.cpu_max or "n/a", r.fps_min or "n/a"), 16, 56 + (i - 1) * 40, 7)
      print(string.format("mem %d KB  frames %d", r.mem_peak, r.frames), 16, 66 + (i - 1) * 40, 7)
    end
    core.center(story.t("press_start"), 210, 6)
  end,
})

return { stages = #STAGES, frames = STAGE_FRAMES }
