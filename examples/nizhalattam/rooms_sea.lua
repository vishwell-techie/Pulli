-- rooms_sea.lua — the rooms of the Leather Sea (see rooms.lua): read while
-- Komali is in the story or at a door into it, let go after. Each room
-- takes what it does not say from the story's defaults, through a metatable.

local SEA = { __index = { place = "sea", sheet = "sea.kolam", bg = "bg_sea.kolam", story = "sea", cast = "sea" } }
local K = function(def) return setmetatable(def, SEA) end        -- (kadal, the sea)

return {
  -- the Leather Sea, the third (cast = false: a room with none of its shadows)
  ["k1.ooru"]    = K{ doors = { "k2.ooru" }, hint = "h_sea" },
  ["k2.ooru"]    = K{ doors = { "k3.ooru" }, fight = true, hint = "h_crab" },
  ["k3.ooru"]    = K{ doors = { "k4.ooru" }, hint = "h_boat" },
  ["k4.ooru"]    = K{ doors = { "k5.ooru" }, shop = "stall", cast = false },
  ["k5.ooru"]    = K{ doors = { "k6.ooru" }, fight = true, hint = "h_wave" },
  ["k6.ooru"]    = K{ doors = { "kboss.ooru" } },
  ["kboss.ooru"] = K{ doors = { "next" }, fight = true, hint = "h_aatta", pick = true, boss = "aattakkaari",
                      boss_sheet = "aatta.kolam", cast = false, taught = "h_dance", tkeys = "b x" },
}
