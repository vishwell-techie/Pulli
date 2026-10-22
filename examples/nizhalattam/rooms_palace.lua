-- rooms_palace.lua — the rooms of the Lamp Palace (see rooms.lua): read while
-- Komali is in the story or at a door into it, let go after. Each room
-- takes what it does not say from the story's defaults, through a metatable.

local PALACE = { __index = { place = "palace", sheet = "palace.kolam", bg = "bg_palace.kolam", story = "palace",
                             cast = "palace" } }
local P = function(def) return setmetatable(def, PALACE) end

-- the words of this story's rooms, in each language (lines.lua reads them
-- while Komali is here)
local words = {
  en = {
    h_palace = "The Lamp Palace. The Queen is held here, and the Puppet King waits",
    h_mirror = "Mirror shades do what you do, a moment later",
    h_cinder = "Cinders burst: strike them from afar, or get away",
    h_guard = "Lamp guards shield their front; their spears reach far",
    h_rani = "The Queen! Three blows break her lamp shield",
    h_lamp = "The Queen's role: %s lamp-fire, %s a shield that turns three blows",
    h_act1 = "The Puppet King. Act one: his soldiers march in from the wings",
    h_act2 = "Act two: the lamps fall, and he throws his crown",
    h_act3 = "Act three: he fights with the moves he has taken",
    curtain = "The curtain falls on the act",
    pick_free = "The King lets one puppet go. Choose:",
    freed = "The %s comes home to the box",
    king_home = "The Puppet King comes home",
    hard_now = "From now on every story is hard, and its boss a shadow",
    ending_b = "The King's shadow tears: the last of the anger he was painted with",
    ending_b2 = "The Puppet Master carves the Jester a role of his own, and the troupe plays a new play, the King and the clown in it together",
  },
  ta = {
    h_palace = "விளக்கு அரண்மனை. ராணி இங்கே சிறைப்பட்டிருக்கிறார்; பாவை அரசன் காத்திருக்கிறான்",
    h_mirror = "கண்ணாடி நிழல்கள் நீ செய்வதையே சற்றுப் பின் செய்யும்",
    h_cinder = "தணல்கள் வெடிக்கும்: தூரத்திலிருந்து அடி, அல்லது விலகு",
    h_guard = "விளக்குக் காவலர்கள் முன்னால் கேடயம் பிடிப்பார்கள்; அவர்கள் ஈட்டி தூரம் எட்டும்",
    h_rani = "ராணி! மூன்று அடிகள் அவரது விளக்குக் கேடயத்தை உடைக்கும்",
    h_lamp = "ராணியின் வேடம்: %s விளக்குத் தீ, %s மூன்று அடிகளைத் தடுக்கும் கேடயம்",
    h_act1 = "பாவை அரசன். முதல் அங்கம்: அவனது வீரர்கள் பக்கவாட்டிலிருந்து வருவார்கள்",
    h_act2 = "இரண்டாம் அங்கம்: விளக்குகள் விழும், அவன் தன் மகுடத்தை எறிவான்",
    h_act3 = "மூன்றாம் அங்கம்: தான் எடுத்துக்கொண்ட அசைவுகளால் அவன் போரிடுவான்",
    curtain = "அங்கத்தின் மேல் திரை விழுகிறது",
    pick_free = "அரசன் ஒரு பாவையை விடுவிக்கிறான். தேர்ந்தெடு:",
    freed = "%s பெட்டிக்குத் திரும்புகிறார்",
    king_home = "பாவை அரசன் வீடு திரும்புகிறான்",
    hard_now = "இனி ஒவ்வொரு கதையும் கடினம்; அதன் தலைவன் ஒரு நிழல்",
    ending_b = "அரசனின் நிழல் கிழிகிறது: அவன் மேல் தீட்டப்பட்ட கோபத்தின் கடைசித் துளி",
    ending_b2 = "ஆசான் கோமாளிக்கென்றே ஒரு வேடம் செதுக்குகிறார்; குழு ஒரு புதிய நாடகம் ஆடுகிறது, அதில் அரசனும் கோமாளியும் சேர்ந்து",
  },
}

return {
  words = words,
  -- the Lamp Palace, always the last story: six rooms, the Queen's hall,
  -- then the Puppet King's stage, an act a room (act)
  ["p1.ooru"]    = P{ doors = { "p2.ooru" }, hint = "h_palace" },
  ["p2.ooru"]    = P{ doors = { "p3.ooru" }, fight = true, hint = "h_mirror" },
  ["p3.ooru"]    = P{ doors = { "p4.ooru" }, hint = "h_cinder" },
  ["p4.ooru"]    = P{ doors = { "p5.ooru" }, shop = "stall", cast = false },
  ["p5.ooru"]    = P{ doors = { "p6.ooru" }, fight = true, hint = "h_guard" },
  ["p6.ooru"]    = P{ doors = { "pboss.ooru" } },
  ["pboss.ooru"] = P{ doors = { "p7.ooru" }, fight = true, hint = "h_rani", pick = true, boss = "rani",
                      boss_sheet = "rani.kolam", cast = false, taught = "h_lamp", tkeys = "b x" },
  ["p7.ooru"]    = P{ doors = { "p8.ooru" }, fight = true, hint = "h_act1", boss = "king", act = 1,
                      boss_sheet = "king.kolam", cast = false },
  ["p8.ooru"]    = P{ doors = { "p9.ooru" }, fight = true, hint = "h_act2", boss = "king", act = 2,
                      boss_sheet = "king.kolam", cast = false },
  ["p9.ooru"]    = P{ doors = { "next" }, fight = true, hint = "h_act3", boss = "king", act = 3,
                      boss_sheet = "king.kolam", cast = false, arrows = true },
}
