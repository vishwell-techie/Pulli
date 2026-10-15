-- title.lua — the title screen, its menu, chapter select and options.
--
-- The art is the top-left 320x240 of sprites.png, logo included. SELECT
-- switches the benchmark on and off (bench.lua); with it on, starting a
-- game runs the benchmark instead.
--
-- Adds the scenes "title", "chapters" and "options".

local scene    = require("scene")
local input    = require("input")
local menu     = require("menu")
local text     = require("text")
local story    = require("story")
local progress = require("progress")

local PLAYABLE = 1                    -- chapters built so far: Kayalur at dusk
local COLORS = { back = 32, border = 10, text = 7, picked = 10 }

local main_menu, sub_menu
local actions = {}                    -- what each item of main_menu does

local function centred(m, y)
  m.x, m.y = 160 - (m.width + 28) // 2, y
  return m
end

local function start(chapter, fresh)
  if fresh then progress.reset() end
  progress.data.started, progress.data.chapter = true, chapter
  progress.save()
  music_stop(300)
  -- The runtime starts every game with the same random numbers. How long
  -- the player took to choose makes each game differ.
  math.randomseed(stat("frame"))
  if progress.bench then scene.go("bench") else scene.go("play", 1, true) end
end

-- The main menu, rebuilt whenever it shows, since the language may change.
local function build()
  local items = {}
  for i = #actions, 1, -1 do actions[i] = nil end
  local function add(key, fn) items[#items + 1] = story.t(key); actions[#actions + 1] = fn end
  if progress.data.started then add("continue", function() start(progress.data.chapter, false) end) end
  add("new_game", function() start(0, true) end)
  if progress.data.started then add("chapters", function() scene.push("chapters") end) end
  add("options", function() scene.push("options") end)
  main_menu = centred(menu.new(items, { colors = COLORS, choose = function(i) actions[i]() end }), 0)
  centred(main_menu, 236 - (#items * main_menu.line + 10))
end

scene.add("title", {
  enter = function()
    build()
    progress.music(0, 600)
  end,
  update = function(dt)
    if input.pressed("select") then progress.bench = not progress.bench end
    main_menu:update()
  end,
  draw = function()
    sspr(0, 0, 320, 240, 0, 0)
    main_menu:draw()
    if progress.bench then
      rectfill(2, 2, text.width(story.t("bench_on")) + 4, 12, 32)
      print(story.t("bench_on"), 4, 4, 8)
    end
  end,
})

-- The chapters reached so far, any of which can be played again.
scene.add("chapters", {
  enter = function()
    local items = {}
    for c = 0, math.min(progress.data.unlocked, PLAYABLE - 1) do items[#items + 1] = story.t("chapter" .. c) end
    items[#items + 1] = story.t("back")
    sub_menu = centred(menu.new(items, {
      colors = COLORS,
      choose = function(i) if i == #items then scene.pop() else start(i - 1, false) end end,
      back = function() scene.pop() end,
    }), 0)
    centred(sub_menu, 120 - (#items * sub_menu.line + 10) // 2)
  end,
  update = function(dt) sub_menu:update() end,
  draw = function() sub_menu:draw() end,
  leave = build,
})

local function option_items()
  local d = progress.data
  return { story.t("language"), story.t(d.music and "music_on" or "music_off"),
           story.t(d.sfx and "sfx_on" or "sfx_off"), story.t("back") }
end

scene.add("options", {
  enter = function()
    sub_menu = menu.new(option_items(), {
      colors = COLORS,
      choose = function(i)
        local d = progress.data
        if i == 1 then
          d.lang = d.lang == "ta" and "en" or "ta"
          story.lang = d.lang
        elseif i == 2 then
          d.music = not d.music
          if d.music then progress.music(0, 300) else music_stop() end
        elseif i == 3 then
          d.sfx = not d.sfx
        else
          scene.pop()
          return
        end
        progress.save()
        sub_menu:set_items(option_items())
        centred(sub_menu, 120 - (4 * sub_menu.line + 10) // 2)
      end,
      back = function() scene.pop() end,
    })
    centred(sub_menu, 120 - (4 * sub_menu.line + 10) // 2)
  end,
  update = function(dt) sub_menu:update() end,
  draw = function() sub_menu:draw() end,
  leave = build,
})

return { playable = PLAYABLE }
