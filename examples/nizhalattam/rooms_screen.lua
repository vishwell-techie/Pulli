-- rooms_screen.lua — the rooms of the Screen (see rooms.lua): read while
-- Komali is in the story or at a door into it, let go after. Each room
-- takes what it does not say from the story's defaults, through a metatable.

local SCREEN = { __index = { place = "screen", sheet = "screen.kolam", bg = "bg_screen.kolam", story = "screen" } }
local S = function(def) return setmetatable(def, SCREEN) end

return {
  -- the Screen, the first story: a lesson a room, then the boss
  ["s1.ooru"]    = S{ doors = { "s2.ooru" }, hint = "h_move", keys = "left right a", start = true,
                      hint2 = "h_high", keys2 = "a" },
  ["s2.ooru"]    = S{ doors = { "s3.ooru" }, fight = true, soft = true, hint = "h_strike", keys = "b" },
  ["s3.ooru"]    = S{ doors = { "s4.ooru" }, fight = true, soft = true, hint = "h_dodge", keys = "y" },
  ["s4.ooru"]    = S{ doors = { "s5.ooru" }, fight = true, soft = true, hint = "h_skill", keys = "x" },
  ["s5.ooru"]    = S{ doors = { "s6.ooru" }, fight = true, hint = "h_fight" },
  ["s6.ooru"]    = S{ doors = { "s7.ooru" }, hint = "h_stall", keys = "up", shop = "stall" },
  ["s7.ooru"]    = S{ doors = { "boss.ooru" }, hint = "h_pit" },
  ["boss.ooru"]  = S{ doors = { "next" }, fight = true, hint = "h_boss", boss = "veeran", pick = true,
                      taught = "h_swap", tkeys = "l r" },
}
