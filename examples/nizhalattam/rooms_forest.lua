-- rooms_forest.lua — the Painted Forest's rooms (see rooms.lua): read while Komali is in
-- the story or next to it, let go after. Each room takes what it does not say
-- from the story's defaults, through a metatable.

local FOREST = { __index = { place = "forest", sheet = "forest.kolam", bg = "bg_forest.kolam", story = "forest",
                             cast = "forest" } }
local NONE = { __index = { place = "forest", sheet = "forest.kolam", bg = "bg_forest.kolam", story = "forest" } }
local F = function(def) return setmetatable(def, FOREST) end
local F0 = function(def) return setmetatable(def, NONE) end      -- a forest room with none of its shadows

return {
  -- the Painted Forest, the second story
  ["f1.ooru"]    = F{ doors = { "f2.ooru" }, hint = "h_forest" },
  ["f2.ooru"]    = F{ doors = { "f3.ooru" }, fight = true, hint = "h_vine", keys = "a" },
  ["f3.ooru"]    = F{ doors = { "f2.ooru", "f4.ooru" }, hint = "h_wisp" },
  ["f4.ooru"]    = F0{ doors = { "f5.ooru" }, shop = "stall" },
  ["f5.ooru"]    = F{ doors = { "f6.ooru" }, fight = true },
  ["f6.ooru"]    = F{ doors = { "fboss.ooru" } },
  ["fboss.ooru"] = F0{ doors = { "next" }, fight = true, hint = "h_vil", pick = true, boss = "vil",
                       boss_sheet = "vil.kolam", arrows = true, taught = "h_aim", tkeys = "up down b" },
}
