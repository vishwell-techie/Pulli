-- script.lua — cut-scenes, written as plain functions that read in order.
--
--   local script = require("script")
--   script.run(function(s)
--     s.say("paati", "pro_1")              -- waits until the player has read it
--     s.walk(kayal, 160, 120, 40)          -- walks there, then carries on
--     s.wait(0.5)
--     s.fade(0.6, 1)                       -- darkens over a second
--     s.during(2, function(dt, k) ... end) -- something every frame for two seconds
--   end, function() ... end)               -- called when it ends
--
-- Each scene runs as a coroutine: a step that takes time yields, and
-- script.update(dt) carries it on next frame. START skips the rest: every
-- step after that finishes at once, putting things where they would have
-- ended up, so a skipped scene leaves the world just as a watched one does.
--
-- Steps work on the world (world.lua) and the actors in it. An actor is any
-- table with x and y, its feet, in map pixels.

local talk     = require("talk")
local story    = require("story")
local core     = require("core")
local progress = require("progress")

local script = { skipping = false }
local co, finish
local w                                 -- the world, given by world.lua

function script.attach(world) w = world end

function script.active() return co ~= nil end

-- Drop the scene running, if any, without finishing it.
function script.cancel() co, finish, script.skipping, progress.quiet = nil, nil, false, false end

function script.run(fn, done)
  co, finish, script.skipping = coroutine.create(function() fn(script) end), done, false
  w.control = false
end

local function stop()
  co = nil
  script.skipping, progress.quiet = false, false
  talk.clear()
  w.control = true
  local f = finish
  finish = nil
  if f then f() end
end

function script.update(dt)
  if not co then return end
  if core.pressed("start") then
    script.skipping, progress.quiet = true, true
    talk.clear()
  end
  local ok, err = coroutine.resume(co, dt)
  if not ok then error(err, 0) end
  if coroutine.status(co) == "dead" then stop() end
end

-- ---- steps ------------------------------------------------------------------

function script.wait(t)
  while t > 0 and not script.skipping do t = t - coroutine.yield() end
end

-- Someone says a line, and the scene waits until it has been read.
function script.say(who, key, ...)
  if script.skipping then return end
  talk.say(story.name(who), story.t(key, ...))
  while talk.active() and not script.skipping do coroutine.yield() end
end

-- Walk an actor to (x, y) at `speed` pixels a second.
function script.walk(a, x, y, speed)
  speed = speed or 40
  a.moving = true
  while not script.skipping do
    local dx, dy = x - a.x, y - a.y
    local d = math.sqrt(dx * dx + dy * dy)
    local step = speed * coroutine.yield()
    if d <= step then break end
    a.x, a.y = a.x + dx / d * step, a.y + dy / d * step
    if math.abs(dx) > math.abs(dy) then a.face = dx < 0 and "left" or "right"
    else a.face = dy < 0 and "up" or "down" end
  end
  a.x, a.y, a.moving = x, y, false
end

-- Change a number on a table smoothly, over t seconds.
function script.tween(obj, key, to, t)
  local from, e = obj[key], 0
  while e < t and not script.skipping do
    e = e + coroutine.yield()
    local k = math.min(1, e / t)
    obj[key] = from + (to - from) * k * (2 - k)
  end
  obj[key] = to
end

function script.fade(level, t) script.tween(w, "fade", level, t or 0.5) end

-- Run something every frame for t seconds: fn(dt, fraction done).
function script.during(t, fn)
  local e = 0
  while e < t and not script.skipping do
    local dt = coroutine.yield()
    e = e + dt
    fn(dt, math.min(1, e / t))
  end
end

return script
