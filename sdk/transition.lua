-- transition.lua — fade or wipe between screens.
--
--   local transition = require("transition")
--
--   -- Fade to black, swap levels while nobody can see, fade back in:
--   transition.through(0.6, function() load_level(2) end)
--
--   function update(dt)
--     transition.update(dt)
--     if transition.busy() then return end   -- if the game should wait meanwhile
--     ...
--   end
--
--   function draw()
--     ... the game ...
--     transition.draw()        -- last, with camera() reset
--   end
--
-- transition.fade_out(seconds, done)   Darken to black; then call done.
-- transition.fade_in(seconds, done)    Brighten from black; then call done.
-- transition.through(seconds, middle, done)   Out, call middle, back in:
--     each half takes half the time.
-- transition.style      "fade" (the palette dims; costs nothing) or "wipe"
--     (a black curtain slides across). Set it before starting one. ("fade")
-- transition.color      The curtain's colour for a wipe (32, black).
-- transition.update(dt) Move it on. Call once a frame.
-- transition.draw()     Draw the curtain for a wipe. Call at the end of draw().
-- transition.busy()     True while one is running.
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local transition = { style = "fade", color = 32 }

local amount = 0                -- 0 clear, 1 fully covered
local from, to, length, time = 0, 0, 0, 0
local after, then_back, middle_time, final = nil, false, 0, nil
local running = false

local function show()
  if transition.style == "fade" then fade(amount) else fade(0) end
end

local function start(goal, seconds, done)
  from, to, length, time, after = amount, goal, math.max(seconds, 0.0001), 0, done
  running = true
end

function transition.fade_out(seconds, done)
  then_back = false
  start(1, seconds, done)
end

function transition.fade_in(seconds, done)
  then_back = false
  amount = 1
  show()
  start(0, seconds, done)
end

function transition.through(seconds, middle, done)
  final, then_back = done, true
  start(1, seconds / 2, middle)
  middle_time = seconds / 2
end

function transition.update(dt)
  if not running then return end
  time = time + dt
  local p = math.min(1, time / length)
  amount = from + (to - from) * p
  show()
  if p >= 1 then
    running = false
    local done = after
    after = nil
    if then_back and to == 1 then           -- the halfway point of through()
      then_back = false
      start(0, middle_time, final)
      final = nil
    end
    if done then done() end
  end
end

function transition.draw()
  if transition.style == "wipe" and amount > 0 then
    rectfill(0, 0, math.ceil(320 * amount), 240, transition.color)
  end
end

function transition.busy()
  return running
end

return transition
