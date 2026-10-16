-- title.lua — the title screen and its menus: the main menu, chapter select
-- and options.
--
-- The art is the top-left 320x240 of sprites.png, logo included. SELECT
-- switches the benchmark on and off (bench.lua); with it on, starting a
-- game runs the benchmark instead, and R turns its stress up. The benchmark is loaded only then, so a
-- player who never asks for it never spends the memory.
--
-- One small menu serves all three screens: a list of items, a box sized to
-- the widest, up and down to move (held, they repeat), A to choose and B to
-- go back.
--
-- Adds the scene "title".

local core     = require("core")
local story    = require("story")
local progress = require("progress")

local PLAYABLE = 7                      -- chapters built so far

local screen = "main"                   -- "main", "chapters" or "options"
local items, actions, pick = {}, {}, 1

local function start(which)
  music_stop(300)
  if progress.bench then
    require("bench")
    core.go("bench")
    return
  end
  if which == "new" then progress.reset() end
  -- The runtime starts every game with the same random numbers. How long
  -- the player took to choose makes each game differ.
  math.randomseed(stat("frame"))
  core.go("play", which == "new" and "opening" or which)
end

-- Fill the menu for a screen. Rebuilt whenever it shows, as the language
-- or the settings may have changed.
local function build(name, keep)
  screen = name
  for i = #items, 1, -1 do items[i], actions[i] = nil, nil end
  local d = progress.data
  local function add(line, fn) items[#items + 1], actions[#items + 1] = line, fn end
  if name == "main" then
    if d.started then add(story.t("continue"), function() start(d.chapter) end) end
    add(story.t("new_game"), function() start("new") end)
    if d.started then add(story.t("chapters"), function() build("chapters") end) end
    add(story.t("options"), function() build("options") end)
  elseif name == "chapters" then
    for c = 0, math.min(d.unlocked, PLAYABLE - 1) do
      add(story.t("chapter" .. c), function() start(c) end)
    end
    add(story.t("back"), function() build("main") end)
  else
    add(story.t("language"), function() d.lang = d.lang == "ta" and "en" or "ta"; story.lang = d.lang end)
    add(story.t(d.music and "music_on" or "music_off"), function()
      d.music = not d.music
      if d.music then progress.music(0, 300) else music_stop() end   -- title music
    end)
    add(story.t(d.sfx and "sfx_on" or "sfx_off"), function() d.sfx = not d.sfx end)
    add(story.t("back"), function() build("main") end)
  end
  pick = keep and math.min(pick, #items) or 1
end

core.add("title", {
  enter = function()
    build("main")
    progress.music(0, 600)   -- title music
  end,
  update = function(dt)
    if core.pressed("select") then progress.bench = not progress.bench end
    if progress.bench and core.pressed("r") then progress.stress = (progress.stress or 1) % 4 * 2 end   -- x1, x2, x4
    if btnp("up") then pick = (pick - 2) % #items + 1; progress.sfx(17) end   -- move
    if btnp("down") then pick = pick % #items + 1; progress.sfx(17) end   -- move
    if core.pressed("a") then
      progress.sfx(18)   -- choose
      local was = screen
      actions[pick]()
      if screen == "options" and was == "options" then
        progress.save()
        build("options", true)
      end
    elseif core.pressed("b") and screen ~= "main" then
      build("main")
    end
  end,
  draw = function()
    sspr(0, 0, 320, 240, 0, 0)
    local line_h, width = 0, 0
    for _, s in ipairs(items) do
      local tw, th = text_size(s)
      width, line_h = math.max(width, tw), math.max(line_h, th + 2)
    end
    local h = #items * line_h + 10
    local x, y = 160 - (width + 28) // 2, screen == "main" and 236 - h or 120 - h // 2
    rectfill(x, y, width + 28, h, 32)
    rect(x, y, width + 28, h, 10)
    for i, s in ipairs(items) do
      local iy = y + 5 + (i - 1) * line_h
      if i == pick then spr(945, x + 6, iy + (line_h - 10) // 2) end
      print(s, x + 18, iy, i == pick and 10 or 7)
    end
    if progress.bench then
      local mark = story.t("bench_on") .. " x" .. (progress.stress or 1)
      rectfill(2, 2, core.width(mark) + 4, 12, 32)
      print(mark, 4, 4, 8)
    end
  end,
})

return { playable = PLAYABLE }
