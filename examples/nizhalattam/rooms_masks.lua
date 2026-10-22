-- rooms_masks.lua — the rooms of the Market of Masks (see rooms.lua): read while
-- Komali is in the story or at a door into it, let go after. Each room
-- takes what it does not say from the story's defaults, through a metatable.

local MASKS = { __index = { place = "masks", sheet = "masks.kolam", bg = "bg_masks.kolam", story = "masks",
                            cast = "masks" } }
local M = function(def) return setmetatable(def, MASKS) end      -- (the market)

-- the words of this story's rooms, in each language (lines.lua reads them
-- while Komali is here)
local words = {
  en = {
    h_masks = "The Market of Masks. The Minister is held here",
    h_twins = "Twin masks swap places when they flash",
    h_juggler = "Jugglers lob knives: watch where they fall",
    h_thief = "A mask thief snatches mai. Catch it: it pays back double",
    h_mandhiri = "The Minister! Which is he? Only he drips ink",
    h_ink = "The Minister's role: %s ink darts slow them, %s a paper decoy draws them off",
  },
  ta = {
    h_masks = "முகமூடிச் சந்தை. மந்திரி இங்கே சிறைப்பட்டிருக்கிறார்",
    h_twins = "இரட்டை முகமூடிகள் மின்னும்போது இடம் மாறும்",
    h_juggler = "வித்தைக்காரர்கள் கத்திகளை எறிவார்கள்: அவை விழும் இடத்தைப் பார்",
    h_thief = "முகமூடித் திருடன் மையைப் பறிப்பான். பிடி: இரட்டிப்பாகத் திருப்பித் தருவான்",
    h_mandhiri = "மந்திரி! எவர் உண்மையானவர்? அவரிடமிருந்து மட்டுமே மை சொட்டும்",
    h_ink = "மந்திரியின் வேடம்: %s மை அம்புகள் அவர்களை மெதுவாக்கும், %s காகிதப் போலி அவர்களை ஈர்க்கும்",
  },
}

return {
  words = words,
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
