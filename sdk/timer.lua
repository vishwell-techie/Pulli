-- timer.lua — do something later, or again and again, and cooldowns.
--
--   local timer = require("timer")
--
--   timer.after(2, function() door_open = true end)        -- in two seconds
--   local blink = timer.every(0.5, function() lit = not lit end)
--   timer.cancel(blink)
--
--   local shot = timer.cooldown(0.25)                      -- a quarter second apart
--   if btn("b") and shot:use() then fire() end
--
--   function update(dt)
--     timer.update(dt)              -- once a frame: runs what is due
--   end
--
-- Timers count game time: they stand still when update() is not called,
-- for instance while a game is paused.
--
-- timer.after(seconds, fn)          Call fn once, that many seconds from now.
-- timer.every(seconds, fn, times)   Call fn every so many seconds, `times`
--     times or for ever. Returns a handle, as after does.
-- timer.cancel(handle)              Stop it. True if it had not yet finished.
--     A handle is good until its timer finishes.
-- timer.clear()                     Stop every timer.
-- timer.count()                     How many are waiting.
-- timer.cooldown(seconds)           An object whose :use() is true, and starts
--     the wait, only when the last use was at least that long ago. Also
--     :ready() to ask without using, and :left() for the seconds to go.
-- timer.update(dt)                  Run whatever is due. Call once a frame.
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local timer = {}

-- Sixty steps of 1/60 do not add up to exactly one second in floating
-- point. Anything due within this much of now counts as due.
local EARLY = 0.0001

local waiting, count = {}, 0
local spare = {}
local cooldowns = setmetatable({}, { __mode = "k" })   -- forgotten when the game drops one

local function add(seconds, fn, every, times)
  if type(fn) ~= "function" then error("timer: give a function to call", 3) end
  local t = table.remove(spare) or {}
  t.left, t.every, t.fn, t.times = seconds, every, fn, times
  count = count + 1
  waiting[count] = t
  return t
end

function timer.after(seconds, fn)
  return add(seconds, fn, nil, 1)
end

function timer.every(seconds, fn, times)
  if seconds <= 0 then error("timer.every: the time between calls must be more than 0", 2) end
  return add(seconds, fn, seconds, times)
end

local function retire(i)
  local t = waiting[i]
  waiting[i] = waiting[count]
  waiting[count] = nil
  count = count - 1
  t.fn = nil
  spare[#spare + 1] = t
end

function timer.cancel(handle)
  for i = 1, count do
    if waiting[i] == handle then retire(i) return true end
  end
  return false
end

function timer.clear()
  for i = count, 1, -1 do retire(i) end
end

function timer.count()
  return count
end

function timer.update(dt)
  for c in pairs(cooldowns) do
    c.wait = c.wait - dt
    if c.wait <= EARLY then c.wait = 0 end
  end
  local i = 1
  while i <= count do
    local t = waiting[i]
    t.left = t.left - dt
    if t.left <= EARLY then
      local fn = t.fn
      if t.times then t.times = t.times - 1 end
      if t.every and (t.times == nil or t.times > 0) then
        t.left = t.left + t.every   -- keep the beat even if a frame ran late
        i = i + 1
      else
        retire(i)                   -- another timer now sits at i
      end
      fn()
    else
      i = i + 1
    end
  end
end

local Cooldown = {}
Cooldown.__index = Cooldown

function timer.cooldown(seconds)
  local c = setmetatable({ length = seconds, wait = 0 }, Cooldown)
  cooldowns[c] = true
  return c
end

function Cooldown:ready() return self.wait <= 0 end
function Cooldown:left() return self.wait end

function Cooldown:use()
  if self.wait > 0 then return false end
  self.wait = self.length
  return true
end

return timer
