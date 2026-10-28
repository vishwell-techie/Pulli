-- rooms_flags.lua — the rooms of the Battlefield of Flags (see rooms.lua): read while
-- Komali is in the story or at a door into it, let go after. Each room
-- takes what it does not say from the story's defaults, through a metatable.

local FLAGS = { __index = { place = "flags", sheet = "flags.kolam", bg = "bg_flags.kolam", story = "flags",
                            cast = "flags" } }
local B = function(def) return setmetatable(def, FLAGS) end      -- (the battlefield)

-- the words of this story's rooms, in each language (lines.lua reads them
-- while Komali is here)
local words = {
  en = {
    h_flags = "The Battlefield of Flags. The Elephant is held here",
    h_bearer = "Shadows near a flag-bearer take half a blow. Tear the flag first",
    h_drum = "The war drum beats: jump its shockwave",
    h_archers = "Archers draw together, then loose: roll through",
    h_yaanai = "The Elephant! His charge ends at a wall: strike him then",
    h_trunk = "The Elephant's role: %s sweeps wide, %s charges them to the wall",
  },
  ta = {
    h_flags = "கொடிகளின் போர்க்களம். யானை இங்கே சிறைப்பட்டிருக்கிறார்",
    h_bearer = "கொடி தாங்கியின் அருகில் நிழல்களுக்குப் பாதி அடிதான். முதலில் கொடியைக் கிழி",
    h_drum = "போர் முரசு முழங்கும்: அதன் அதிர்வலையைத் தாண்டு",
    h_archers = "வில்லாளிகள் ஒன்றாக நாண் இழுத்து எய்வார்கள்: ஊடே உருள்",
    h_yaanai = "யானை! அவரது பாய்ச்சல் சுவரில் முடியும்: அப்போது அடி",
    h_trunk = "யானையின் வேடம்: %s அகலமாக வீசும், %s அவர்களைச் சுவர்வரை தள்ளும்",
  },
}

return {
  words = words,
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
