-- rooms_forest.lua — the rooms of the Painted Forest (see rooms.lua): read while
-- Komali is in the story or at a door into it, let go after. Each room
-- takes what it does not say from the story's defaults, through a metatable.

local FOREST = { __index = { place = "forest", sheet = "forest.kolam", bg = "bg_forest.kolam", story = "forest",
                             cast = "forest" } }
local NONE = { __index = { place = "forest", sheet = "forest.kolam", bg = "bg_forest.kolam", story = "forest" } }
local F = function(def) return setmetatable(def, FOREST) end
local F0 = function(def) return setmetatable(def, NONE) end      -- a forest room with none of its shadows

-- the words of this story's rooms, in each language (lines.lua reads them
-- while Komali is here)
local words = {
  en = {
    h_forest = "The Painted Forest. The Archer is held here",
    h_vine = "Vine-hands wait under the leaves. Caught? %s shakes free",
    h_wisp = "Wisps drift through the trees, and fade",
    h_vil = "The Archer! Close in: he leaps away",
    h_aim = "The Archer's role: hold %s or %s to aim, hold %s to pierce",
  },
  ta = {
    h_forest = "வண்ணக் காடு. வில்லாளி வில் இங்கே சிறைப்பட்டிருக்கிறார்",
    h_vine = "இலைகளுக்குக் கீழே கொடிக் கைகள் காத்திருக்கின்றன. பிடிபட்டாயா? %s உதறும்",
    h_wisp = "ஆவிகள் மரங்களின் ஊடே மிதந்து மறையும்",
    h_vil = "வில்! நெருங்கிப் போ: அவர் தாவி விலகுவார்",
    h_aim = "வில்லின் வேடம்: குறி வைக்க %s அல்லது %s, துளைக்க %s-ஐ அழுத்திப் பிடி",
  },
}

return {
  words = words,
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
