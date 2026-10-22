-- rooms_masks.lua — the Market of Masks's rooms (see rooms.lua): read while Komali is in
-- the story or next to it, let go after. Each room takes what it does not say
-- from the story's defaults, through a metatable.

local MASKS = { __index = { place = "masks", sheet = "masks.kolam", bg = "bg_masks.kolam", story = "masks",
                            cast = "masks" } }
local M = function(def) return setmetatable(def, MASKS) end      -- (the market)

return {
  -- the Market of Masks, the fifth (the Minister's darts fly as arrows do)
  ["m1.ooru"]    = M{ doors = { "m2.ooru" }, hint = "h_masks" },
  ["m2.ooru"]    = M{ doors = { "m3.ooru" }, fight = true, hint = "h_twins" },
  ["m3.ooru"]    = M{ doors = { "m4.ooru" }, hint = "h_juggler" },
  ["m4.ooru"]    = M{ doors = { "m5.ooru" }, shop = "stall", cast = false },
  ["m5.ooru"]    = M{ doors = { "m6.ooru" }, fight = true, hint = "h_thief" },
  ["m6.ooru"]    = M{ doors = { "mboss.ooru" } },
  ["mboss.ooru"] = M{ doors = { "next" }, fight = true, hint = "h_mandhiri", pick = true, boss = "mandhiri",
                      boss_sheet = "mandhiri.kolam", cast = false, arrows = true, taught = "h_ink", tkeys = "b x" },
}
