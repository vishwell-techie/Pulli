-- rooms_sea.lua — the rooms of the Leather Sea (see rooms.lua): read while
-- Komali is in the story or at a door into it, let go after. Each room
-- takes what it does not say from the story's defaults, through a metatable.

local SEA = { __index = { place = "sea", sheet = "sea.kolam", bg = "bg_sea.kolam", story = "sea", cast = "sea" } }
local K = function(def) return setmetatable(def, SEA) end        -- (kadal, the sea)

-- the words of this story's rooms, in each language (lines.lua reads them
-- while Komali is here)
local words = {
  en = {
    h_sea = "The Leather Sea. The Dancer is held here",
    h_crab = "Crab-shields guard their front. Strike as they rest after a lunge",
    h_boat = "Ride the boats across the water. Mind the gulls' cry",
    h_wave = "A wave-cutter rides the quay: jump it, strike when its wave sinks",
    h_aatta = "The Dancer! Her bells ring before she moves",
    h_dance = "The Dancer's role: %s kicks carry you on, %s dashes through and stuns",
  },
  ta = {
    h_sea = "தோல் கடல். ஆட்டக்காரி இங்கே சிறைப்பட்டிருக்கிறார்",
    h_crab = "நண்டுக் கேடயங்கள் முன்பக்கத்தைக் காக்கும். பாய்ந்த பின் ஓயும்போது அடி",
    h_boat = "படகுகளில் ஏறிக் கடலைக் கட. கடற்பறவையின் கூவலுக்குக் கவனம்",
    h_wave = "அலைவெட்டி துறைமேடையில் சவாரி செய்யும்: தாண்டு, அலை தணியும்போது அடி",
    h_aatta = "ஆட்டக்காரி! அவர் அசையும் முன் சலங்கைகள் ஒலிக்கும்",
    h_dance = "ஆட்டக்காரியின் வேடம்: %s உதைகள் முன்னே கொண்டுசெல்லும், %s ஊடே பாய்ந்து திகைக்க வைக்கும்",
  },
}

return {
  words = words,
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
