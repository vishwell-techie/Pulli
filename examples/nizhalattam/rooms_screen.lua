-- rooms_screen.lua — the rooms of the Screen (see rooms.lua): read while
-- Komali is in the story or at a door into it, let go after. Each room
-- takes what it does not say from the story's defaults, through a metatable.

local SCREEN = { __index = { place = "screen", sheet = "screen.kolam", bg = "bg_screen.kolam", story = "screen" } }
local S = function(def) return setmetatable(def, SCREEN) end

-- the words of this story's rooms, in each language (lines.lua reads them
-- while Komali is here)
local words = {
  en = {
    h_move = "%s %s walk    %s jump",
    h_high = "Hold %s to jump higher",
    h_strike = "%s strikes: press again, and again",
    h_dodge = "He winds up, then strikes. %s rolls through the blow",
    h_skill = "%s is your skill: a pratfall trips them all",
    h_fight = "Strike from behind, or while they rest",
    h_stall = "%s at the stall to spend mai",
    h_pit = "From here on, mind the pits",
    h_boss = "The Warrior! Watch each move before it comes",
    h_swap = "%s %s change role: the new one strikes as it comes",
  },
  ta = {
    h_move = "%s %s நட    %s தாவு",
    h_high = "உயரத் தாவ %s-ஐ அழுத்திப் பிடி",
    h_strike = "%s அடி: மீண்டும், மீண்டும் அழுத்து",
    h_dodge = "அவன் ஓங்குவான், பிறகு அடிப்பான். %s அடியின் ஊடே உருளும்",
    h_skill = "%s உன் திறமை: விழுந்து எல்லோரையும் இடற வை",
    h_fight = "பின்னால் இருந்தோ, அவர்கள் ஓயும்போதோ அடி",
    h_stall = "மை செலவழிக்கக் கடையில் %s",
    h_pit = "இனி குழிகள் உண்டு, கவனம்",
    h_boss = "வீரன்! ஒவ்வொரு அசைவையும் முன்பே பார்",
    h_swap = "%s %s வேடம் மாற்று: புதியது வரும்போதே அடிக்கும்",
  },
}

return {
  words = words,
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
