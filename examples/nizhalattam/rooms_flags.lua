-- rooms_flags.lua — the Battlefield of Flags's rooms (see rooms.lua): read while Komali is in
-- the story or next to it, let go after. Each room takes what it does not say
-- from the story's defaults, through a metatable.

local FLAGS = { __index = { place = "flags", sheet = "flags.kolam", bg = "bg_flags.kolam", story = "flags",
                            cast = "flags" } }
local B = function(def) return setmetatable(def, FLAGS) end      -- (the battlefield)

return {
  -- the Battlefield of Flags, the fourth (its archers want arrows)
  ["b1.ooru"]    = B{ doors = { "b2.ooru" }, hint = "h_flags" },
  ["b2.ooru"]    = B{ doors = { "b3.ooru" }, fight = true, hint = "h_bearer" },
  ["b3.ooru"]    = B{ doors = { "b4.ooru" }, hint = "h_drum" },
  ["b4.ooru"]    = B{ doors = { "b5.ooru" }, shop = "stall", cast = false },
  ["b5.ooru"]    = B{ doors = { "b6.ooru" }, fight = true, hint = "h_archers", arrows = true },
  ["b6.ooru"]    = B{ doors = { "bboss.ooru" }, arrows = true },
  ["bboss.ooru"] = B{ doors = { "next" }, fight = true, hint = "h_yaanai", pick = true, boss = "yaanai",
                      boss_sheet = "yaanai.kolam", cast = false, taught = "h_trunk", tkeys = "b x" },
}
