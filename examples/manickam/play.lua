-- play.lua — the game being played: the chapters in order, the top bar,
-- pausing (with a map of the region) and being caught.
--
--   core.go("play", "opening")     -- a new game: the opening, then chapter 0
--   core.go("play", 3)             -- chapter 3, the lotus lake
--
-- Each chapter is a region module (ch0.lua ... ch6.lua), loaded the first
-- time it is played.
--
-- Adds the scenes "play", "pause" and "over".

local core     = require("core")
local talk     = require("talk")
local fx       = require("fx")
local story    = require("story")
local progress = require("progress")
local w        = require("world")

local play = { debug = false }

-- The chapter is over. After chapters 1 to 5 Paati tells one of her
-- stories, as Kayal remembers it; then on to the next.
function w.finish()
  local ch, d = w.chapter, progress.data
  w.control = false
  d.unlocked, d.chapter = math.max(d.unlocked, ch + 1), math.min(ch + 1, 6)
  progress.checkpoint()
  music_stop(600)
  -- The next chapter starts with the hearts that are left, and Paati's
  -- story, told after chapters 1 to 5, gives one back.
  local told = ch >= 1 and ch <= 5
  if ch < 6 then w.carry = math.min(w.p.hearts + (told and 1 or 0), d.hearts) end
  local function next() core.through(1.2, function() core.go(ch < 6 and "play" or "title", ch + 1) end) end
  if told then
    progress.music(0, 600)   -- title music
    talk.say(story.t("story"), story.t("st" .. ch), next)
  else
    next()
  end
end

-- The ruby's seven pieces, found or not, in a row from x.
local function ring(x, y)
  for i = 0, 6 do spr(progress.data.pieces >> i & 1 == 1 and 944 or 953, x + i * 10, y) end
end

core.add("play", {
  -- Loading a chapter (its module and a scan of its whole map) takes a
  -- moment, all in one frame. So entering only asks for it: the loading
  -- screen fades in and stays a little while, then the work is done
  -- behind it.
  enter = function(which)
    local d = progress.data
    if which ~= "opening" then
      d.started, d.chapter, d.unlocked = true, which, math.max(d.unlocked, which)
      progress.checkpoint()
    end
    play.loading, play.shown, play.wait = which, false, 0.6
  end,
  update = function(dt)
    local which = play.loading
    if which ~= nil then
      play.wait = play.wait - dt
      if not play.shown or play.wait > 0 or core.busy() then return end
      play.loading = nil
      dbg("chapter " .. tostring(which))
      collectgarbage()                    -- room to load the region in
      w.start(which == "opening" and 0 or which, require(which == "opening" and "opening" or "ch" .. which))
      return
    end
    if core.pressed("select") and w.control then play.debug = not play.debug end
    w.update(dt)
  end,
  draw = function()
    if play.loading ~= nil then           -- the loading screen: the chapter's name, and Minmini
      local which, f = play.loading, stat("frame")
      cls(32)
      if which ~= "opening" then
        local num = story.t("chapter", which)
        core.center(num, 92, 9)
        core.center(story.t("chapter" .. which), 96 + core.height(num), 10, 41)
      end
      circ(160, 160, 4 + f // 6 % 2, 10)
      spr(936 + f // 5 % 2, 156, 156)
      play.shown = true
      return
    end
    local p, r, f = w.p, w.region, stat("frame")
    cls(0)
    w.draw_world()
    -- the top bar: hearts, the ruby, keys, and Minmini, dim while her flare
    -- comes back
    if not r.no_hud then
      rectfill(0, 0, 320, 12, 32)
      for i = 1, progress.data.hearts do spr(i <= p.hearts and 938 or 939, i * 9 - 6, 2) end
      ring(116, 2)
      if w.keys > 0 then spr(943, 196, 2) print(w.keys, 206, 3, 7) end
      if w.flare_cd > 0 then pal(10, 41) pal(23, 41) end
      spr(936, 308, 2)
      pal()
      if r.hud then r.hud(w) end
    end
    if w.flash > 0.6 then rectfill(0, 0, 320, 240, 7)
    elseif w.flash > 0 then for y = f % 2, 239, 2 do rectfill(0, y, 320, 1, 7) end end
    talk.draw()
    -- the chapter's name, for a few seconds as it begins
    if w.card_t > 0 and (w.card_t > 0.6 or f % 4 < 2) then
      local name, num = story.t("chapter" .. w.chapter), story.t("chapter", w.chapter)
      local nh = core.height(num)
      local h = core.height(name) + nh + 14
      rectfill(0, 60, 320, h, 32)
      rect(-1, 60, 322, h, 9)
      core.center(num, 65, 9)
      core.center(name, 68 + nh, 10, 41)
    end
    -- SELECT while playing: how hard the machine is working
    if play.debug then
      rectfill(0, 14, 320, 10, 32)
      print(string.format("fps %s cpu %s mem %dK spr %d fx %d slimes %d", stat("fps") or "-", stat("cpu") or "-",
        stat("mem") // 1, w.sprites or 0, fx.n, #w.slimes), 2, 15, 11)
    end
    if not core.busy() then fade(w.fade) end
  end,
  leave = function()
    fade(0)
    if w.region and w.region.leave and play.loading == nil then w.region.leave(w) end
  end,
})

-- ---- pause: a map of the region, and what has been found -------------------------------
-- The map is worked out when the game pauses, as runs of one colour along
-- each row, kept as strings of two bytes a run, and let go on leaving.

local mini, ms, mx, my
-- a colour for each tile flag, the first that matches: deep, water, thorns,
-- lamp, solid, dark; else ground
local FLAG_COLOURS = { 8, 28, 2, 12, 4, 2, 32, 10, 1, 5, 16, 50 }

core.add("pause", {
  enter = function()
    music_pause(true)
    progress.sfx(4)   -- pause
    local tw, th = map.size()
    ms = math.max(1, math.min(160 // tw, 168 // th))
    mx, my, mini = 16 + (160 - tw * ms) // 2, 40 + (168 - th * ms) // 2, {}
    local row = {}
    for cy = 0, th - 1 do
      local n, last, len = 0, -1, 0
      for cx = 0, tw - 1 do
        local t = map.get(0, cx, cy)
        local fl, c = map.flags(t), (t == 42 or t == 49 or t == 55 or t == 112) and 15 or 3
        for i = 1, #FLAG_COLOURS, 2 do
          if fl & FLAG_COLOURS[i] ~= 0 then c = FLAG_COLOURS[i + 1] break end
        end
        if map.get(1, cx, cy) ~= 0 then c = 35 end        -- under the trees
        if c == last and len < 255 then len = len + 1
        else
          if len > 0 then row[n + 1], row[n + 2], n = last, len, n + 2 end
          last, len = c, 1
        end
      end
      row[n + 1], row[n + 2] = last, len
      mini[cy + 1] = string.char(table.unpack(row, 1, n + 2))
    end
  end,
  update = function(dt)
    if core.pressed("start") or core.pressed("select") then
      music_pause(false)
      if core.pressed("start") then progress.sfx(5) core.pop()   -- resume
      else music_stop() core.go("title") end
    end
  end,
  draw = function()
    local d, f = progress.data, stat("frame")
    cls(32)
    core.center(story.t("chapter" .. w.chapter), 14, 9)
    for cy, runs in ipairs(mini) do
      local x = mx
      for i = 1, #runs, 2 do
        local c, len = runs:byte(i, i + 1)
        rectfill(x, my + (cy - 1) * ms, len * ms, ms, c)
        x = x + len * ms
      end
    end
    for _, l in ipairs(w.lamps) do
      if l.lit then rectfill(mx + l.cx * ms, my + l.cy * ms, ms, ms, 10) end
    end
    if f // 10 % 2 == 0 then rectfill(mx + w.p.x // 8 * ms - 1, my + w.p.y // 8 * ms - 1, ms + 2, ms + 2, 8) end
    local y = 44
    for i, key in ipairs({ "pieces", "hearts", "side" }) do
      print(story.t(key), 188, y, 10)
      y = y + core.height(story.t(key)) + 3
      if i == 1 then ring(188, y)
      elseif i == 2 then for k = 1, d.hearts do spr(938, 179 + k * 9, y) end
      else
        spr(941, 188, y) print(d.pots .. "/3", 200, y, 7)
        spr(942, 236, y) print(d.lotuses .. "/7", 248, y, 7)
        if d.lamp then spr(940, 284, y) end
      end
      y = y + 16
    end
    core.center(story.t("paused"), 186, 7)
    core.center(story.t("resume"), 230 - core.height(story.t("resume")), 6)
  end,
  leave = function() mini = nil end,
})

-- ---- caught by the dark --------------------------------------------------------------------

core.add("over", {
  enter = function() w.fade, w.over_t = 0, 0 end,
  update = function(dt)
    w.over_t = w.over_t + dt
    if w.over_t > 1.5 and (core.pressed("a") or core.pressed("start")) and not core.busy() then
      core.through(1, function() core.go("title") end)
    end
  end,
  draw = function()
    local t, f = w.over_t, stat("frame")
    cls(32)
    for i = 0, 60 do pset(i * 53 % 320, (i * 97 + f // 3) % 240, i % 4 == 0 and 2 or 50) end   -- the dark, drifting
    core.center(story.t("game_over"), 70, 8, 2)
    core.center(story.t("caught"), 100, 6)
    ring(126, 136)
    if t > 1.5 and f // 20 % 2 == 0 then core.center(story.t("retry"), 186, 7) end
  end,
})

return play
