-- core.lua — the game's own small versions of four SDK helpers: scene,
-- input, transition and text.
--
--   local core = require("core")
--   core.add("title", { enter = fn, update = fn, draw = fn, leave = fn })
--   core.go("play", 3)      core.push("pause")      core.pop()
--   if core.pressed("a") then ... end              -- once per press
--   core.through(1, function() core.go("play", 1) end)   -- fade out, swap, in
--   core.center("PAUSED", 100, 7)   core.wrap(s, 36)   core.width(s)
--
-- Why not the SDK's? On the console every Lua function costs memory for as
-- long as the game runs, and a module, once loaded, is never let go. The
-- SDK helpers are written to be read and to cover every case; this game
-- needs a few cases of each and all the memory it can get, so it keeps
-- these four together in fewer, larger functions. A game with memory to
-- spare is better off with the SDK's.

local core = {}

-- ---- scenes: a stack, the top one updated, all of them drawn ------------------
local scenes, stack, change = {}, {}, nil

function core.add(name, s) scenes[name] = s end

local function apply()
  local how, name, a, b = change[1], change[2], change[3], change[4]
  change = nil
  if how ~= "push" then
    for i = #stack, how == "pop" and #stack or 1, -1 do
      local s = scenes[stack[i]]
      stack[i] = nil
      if s.leave then s.leave() end
    end
  end
  if how ~= "pop" then
    stack[#stack + 1] = name
    if scenes[name].enter then scenes[name].enter(a, b) end
  end
end

function core.go(name, a, b) change = { "go", name, a, b } end
function core.push(name, a, b) change = { "push", name, a, b } end
function core.pop() change = { "pop" } end
function core.current() return stack[#stack] end

-- ---- buttons that count once a press ---------------------------------------------
local NAMES = { "left", "right", "up", "down", "a", "b", "x", "y", "l", "r", "start", "select" }
local was, now = {}, {}

function core.pressed(b) return now[b] and not was[b] end

-- ---- fading out and back in --------------------------------------------------------
local level, goal, speed, middle, sent = 0, 0, 0, nil, 0

function core.through(seconds, fn)
  goal, speed, middle = 1, 2 / seconds, fn
end

function core.busy() return goal ~= level end

-- Read the buttons, move a fade on, and update the top scene. Once a frame.
function core.update(dt)
  for i = 1, #NAMES do
    local b = NAMES[i]
    was[b], now[b] = now[b], btn(b)
  end
  if goal ~= level then
    if goal > level then
      level = math.min(goal, level + speed * dt)
      if level == goal and middle then
        local fn = middle
        middle, goal = nil, 0
        fn()
      end
    else
      level = math.max(goal, level - speed * dt)
    end
  end
  if change then apply() end
  local top = scenes[stack[#stack]]
  if top and top.update then top.update(dt) end
  if change then apply() end
end

function core.draw()
  for i = 1, #stack do
    local s = scenes[stack[i]]
    if s.draw then s.draw() end
  end
  if level > 0 or sent > 0 then fade(level) sent = level end
end

-- ---- text ------------------------------------------------------------------------
function core.width(s) return (text_size(s)) end
function core.height(s) local _, h = text_size(s) return h end

function core.center(s, y, c, outline)
  local x = 160 - core.width(s) // 2
  if outline then
    for d = -1, 1, 2 do print(s, x + d, y, outline) print(s, x, y + d, outline) end
  end
  print(s, x, y, c)
end

-- Break text into lines at most `columns` * 8 pixels wide, at spaces. A
-- word longer than a line is left whole; the game has none.
function core.wrap(s, columns)
  local lines, room = {}, columns * 8
  for para in (s .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      if line == "" then line = word
      elseif core.width(line .. " " .. word) <= room then line = line .. " " .. word
      else lines[#lines + 1], line = line, word end
    end
    lines[#lines + 1] = line
  end
  return lines
end

return core
