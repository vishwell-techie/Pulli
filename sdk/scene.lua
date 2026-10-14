-- scene.lua — a game's screens: title, play, pause, game over.
--
--   local scene = require("scene")
--
--   scene.add("title", {
--     update = function(dt) if btnp("start") then scene.go("play") end end,
--     draw   = function() cls() print("PRESS START", 116, 116, 7) end,
--   })
--   scene.add("play", {
--     enter  = function(level) load_level(level or 1) end,
--     update = function(dt) ... if btnp("start") then scene.push("pause") end end,
--     draw   = function() ... end,
--   })
--   scene.add("pause", {
--     update = function(dt) if btnp("start") then scene.pop() end end,
--     draw   = function() print("PAUSED", 136, 116, 7) end,   -- drawn over play
--   })
--
--   function init()     scene.go("title") end
--   function update(dt) scene.update(dt) end
--   function draw()     scene.draw() end
--
-- A scene is a table with any of: enter(...), update(dt), draw(), leave().
--
-- scene.add(name, s)     Make a scene known by a name.
-- scene.go(name, ...)    Leave every scene on screen and enter this one,
--     passing it the extra arguments.
-- scene.push(name, ...)  Enter a scene over the one on screen, which stops
--     updating but is still drawn beneath it: for pause screens and menus.
-- scene.pop()            Leave the top scene and return to the one beneath.
-- scene.update(dt)       Update the top scene. Call from update().
-- scene.draw()           Draw every scene on screen, bottom first.
-- scene.current()        The name of the top scene.
--
-- A change asked for during an update happens once that update is over, so
-- a scene never finds itself half left.
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local scene = {}

local scenes = {}
local stack = {}                -- names, bottom first
local updating = false
local pending = nil             -- { how, name, args } waiting for the update to end

function scene.add(name, s)
  scenes[name] = s
end

local function get(name)
  local s = scenes[name]
  if not s then error("scene: no scene called '" .. tostring(name) .. "'", 4) end
  return s
end

local function call(name, fn, ...)
  local f = scenes[name][fn]
  if f then f(...) end
end

local function apply(how, name, args)
  if how == "go" then
    get(name)
    for i = #stack, 1, -1 do
      call(stack[i], "leave")
      stack[i] = nil
    end
    stack[1] = name
    call(name, "enter", table.unpack(args, 1, args.n))
  elseif how == "push" then
    get(name)
    stack[#stack + 1] = name
    call(name, "enter", table.unpack(args, 1, args.n))
  elseif #stack > 0 then
    call(stack[#stack], "leave")
    stack[#stack] = nil
  end
end

local function change(how, name, ...)
  if how ~= "pop" then get(name) end
  local args = table.pack(...)
  if updating then
    pending = { how = how, name = name, args = args }
  else
    apply(how, name, args)
  end
end

function scene.go(name, ...) change("go", name, ...) end
function scene.push(name, ...) change("push", name, ...) end
function scene.pop() change("pop") end

function scene.update(dt)
  local top = stack[#stack]
  if not top then return end
  updating = true
  call(top, "update", dt)
  updating = false
  if pending then
    local p = pending
    pending = nil
    apply(p.how, p.name, p.args)
  end
end

function scene.draw()
  for i = 1, #stack do call(stack[i], "draw") end
end

function scene.current()
  return stack[#stack]
end

return scene
