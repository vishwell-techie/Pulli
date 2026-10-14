-- tween.lua — change numbers smoothly over time.
--
--   local tween = require("tween")
--
--   tween.to(box, { x = 200, y = 40 }, 0.5, "out_quad")   -- half a second
--   tween.to(door, { open = 1 }, 1, "linear", function() sfx(3) end)
--
--   function update(dt)
--     tween.update(dt)            -- once a frame; moves every running tween
--   end
--
-- tween.to(target, goals, seconds, ease, done)
--   Takes each field named in `goals` from the value it has in `target` now
--   to the value given, over `seconds`. `ease` is a name from tween.ease or
--   your own function of 0..1; it defaults to "out_quad". `done`, if given,
--   is called once when the tween arrives. Returns a handle for tween.stop.
-- tween.stop(handle)   Stop one tween where it is. The handle is good until
--                      its tween ends; after that it may belong to another.
-- tween.stop_all(target)   Stop every tween on `target`, or every tween at
--                          all if no target is given.
-- tween.count()        How many are running.
--
-- This file is part of the Pulli SDK. Copy it into your game and change it
-- as you like.

local tween = {}

-- Sixty steps of 1/60 do not add up to exactly one second in floating
-- point. A tween this close to its end counts as arrived.
local EARLY = 0.0001

local running, count = {}, 0    -- running[1..count]
local spare = {}                -- finished tweens, kept to be used again

-- Each takes how far through the time we are, 0 to 1, and gives how far
-- through the change to be. See them drawn at https://easings.net
tween.ease = {
  linear   = function(t) return t end,
  in_quad  = function(t) return t * t end,
  out_quad = function(t) return t * (2 - t) end,
  in_out_quad = function(t)
    if t < 0.5 then return 2 * t * t end
    return 1 - 2 * (1 - t) * (1 - t)
  end,
  in_cubic  = function(t) return t * t * t end,
  out_cubic = function(t) t = 1 - t; return 1 - t * t * t end,
  in_out_cubic = function(t)
    if t < 0.5 then return 4 * t * t * t end
    t = 1 - t
    return 1 - 4 * t * t * t
  end,
  -- goes a little past the goal and settles back
  out_back = function(t)
    t = t - 1
    return 1 + t * t * (2.70158 * t + 1.70158)
  end,
  -- lands and bounces, like a dropped ball
  out_bounce = function(t)
    if t < 1 / 2.75 then return 7.5625 * t * t end
    if t < 2 / 2.75 then t = t - 1.5 / 2.75; return 7.5625 * t * t + 0.75 end
    if t < 2.5 / 2.75 then t = t - 2.25 / 2.75; return 7.5625 * t * t + 0.9375 end
    t = t - 2.625 / 2.75
    return 7.5625 * t * t + 0.984375
  end,
}

function tween.to(target, goals, seconds, ease, done)
  ease = ease or "out_quad"
  local curve = type(ease) == "function" and ease or tween.ease[ease]
  if not curve then error("tween.to: no ease called '" .. tostring(ease) .. "'", 2) end
  if type(seconds) ~= "number" then error("tween.to: say how many seconds it should take", 2) end

  local t = table.remove(spare) or { from = {}, to = {} }
  for k in pairs(t.from) do t.from[k], t.to[k] = nil, nil end
  for k, goal in pairs(goals) do
    if type(target[k]) ~= "number" then error("tween.to: '" .. tostring(k) .. "' is not a number", 2) end
    t.from[k], t.to[k] = target[k], goal
  end
  t.target, t.curve, t.done = target, curve, done
  t.time, t.length = 0, seconds
  count = count + 1
  running[count] = t
  return t
end

-- Take running[i] out, filling its place with the last one.
local function retire(i)
  local t = running[i]
  running[i] = running[count]
  running[count] = nil
  count = count - 1
  t.target, t.done = nil, nil
  spare[#spare + 1] = t
end

function tween.update(dt)
  local i = 1
  while i <= count do
    local t = running[i]
    t.time = t.time + dt
    if t.time >= t.length - EARLY then
      for k, goal in pairs(t.to) do t.target[k] = goal end   -- land exactly
      local done = t.done
      retire(i)                   -- another tween now sits at i: do not move on
      if done then done() end
    else
      local p = t.curve(t.time / t.length)
      for k, goal in pairs(t.to) do
        t.target[k] = t.from[k] + (goal - t.from[k]) * p
      end
      i = i + 1
    end
  end
end

function tween.stop(handle)
  for i = 1, count do
    if running[i] == handle then retire(i) return true end
  end
  return false
end

function tween.stop_all(target)
  for i = count, 1, -1 do
    if target == nil or running[i].target == target then retire(i) end
  end
end

function tween.count()
  return count
end

return tween
