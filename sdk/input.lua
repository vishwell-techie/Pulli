-- input.lua — button presses that fire once, releases, and how long held.
--
--   local input = require("input")
--
--   function update(dt)
--     input.update(dt)                -- first thing, once a frame
--     if input.pressed("a") then jump() end        -- once per press, never repeats
--     if input.released("b") then fire(charge) end
--     charge = input.held("b")        -- seconds B has been down, 0 when up
--   end
--
-- btnp() repeats while a button is held, which suits moving through a menu.
-- For jumping, confirming and firing, a press must count once: use this.
--
-- input.update(dt)      Read the buttons. Call once a frame, before the rest.
-- input.pressed(b)      True on the frame b went down.
-- input.released(b)     True on the frame b came up.
-- input.held(b)         Seconds b has been down; 0 if it is up.
-- input.any()           The name of a button pressed this frame, or nil.
--
-- Buttons are named as for btn(): "left", "right", "up", "down", "a", "b",
-- "x", "y", "l", "r", "start", "select".
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local input = {}

local NAMES = { "left", "right", "up", "down", "a", "b", "x", "y", "l", "r", "start", "select" }
local down, was, held = {}, {}, {}
for i = 1, #NAMES do
  local n = NAMES[i]
  -- A button already down when the game starts does not count as a press.
  down[n], was[n], held[n] = true, true, 0
end
local first = true

local function known(b)
  if down[b] == nil then error("input: no button called '" .. tostring(b) .. "'", 3) end
end

function input.update(dt)
  for i = 1, #NAMES do
    local n = NAMES[i]
    was[n] = down[n]
    down[n] = btn(n)
    if first then was[n] = down[n] end
    held[n] = down[n] and (was[n] and held[n] + dt or dt) or 0
  end
  first = false
end

function input.pressed(b)
  known(b)
  return down[b] and not was[b]
end

function input.released(b)
  known(b)
  return was[b] and not down[b]
end

function input.held(b)
  known(b)
  return held[b]
end

function input.any()
  for i = 1, #NAMES do
    local n = NAMES[i]
    if down[n] and not was[n] then return n end
  end
  return nil
end

return input
