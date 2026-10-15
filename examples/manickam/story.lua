-- story.lua — every word the game shows, in Tamil and in English.
--
--   local story = require("story")
--   story.lang = "en"                  -- or "ta"
--   print(story.t("new_game"), 8, 8, 7)
--
-- A key missing from one language falls back to English, then to the key
-- itself, so a missing line shows up as its name rather than nothing.

local story = { lang = "ta" }

local LINES = {
  en = {
    new_game = "New game", continue = "Continue", chapters = "Chapters", options = "Options",
    back = "Back", press_start = "PRESS START",
    language = "Language: English", music_on = "Music: on", music_off = "Music: off",
    sfx_on = "Sounds: on", sfx_off = "Sounds: off",
    paused = "PAUSED", resume = "START: ON   SELECT: TITLE",
    clear = "LEVEL %d CLEAR", next = "PRESS A FOR THE NEXT",
    won = "YOU FOUND THEM ALL!", again = "PRESS A TO PLAY AGAIN",
    out_of_time = "OUT OF TIME", caught = "THE SLIMES GOT YOU", retry = "PRESS A TO TRY AGAIN",
    chapter0 = "Kayalur at dusk", chapter1 = "The paddy fields", chapter2 = "The banyan forest",
    chapter3 = "The lotus lake", chapter4 = "The thorny hills", chapter5 = "The temple",
    chapter6 = "Karthigai Deepam",
    bench_on = "BENCHMARK ON", bench_title = "BENCHMARK", bench_done = "BENCHMARK DONE",
  },
  ta = {
    new_game = "புதிய விளையாட்டு", continue = "தொடர்க", chapters = "அத்தியாயங்கள்", options = "அமைப்புகள்",
    back = "பின்செல்", press_start = "தொடங்க START அழுத்துக",
    language = "மொழி: தமிழ்", music_on = "இசை: உண்டு", music_off = "இசை: இல்லை",
    sfx_on = "ஒலிகள்: உண்டு", sfx_off = "ஒலிகள்: இல்லை",
    paused = "இடைநிறுத்தம்", resume = "START: தொடர்   SELECT: முகப்பு",
    clear = "நிலை %d முடிந்தது", next = "அடுத்ததற்கு A",
    won = "எல்லாம் கிடைத்தன!", again = "மீண்டும் விளையாட A",
    out_of_time = "நேரம் முடிந்தது", caught = "இருள் பிடித்தது", retry = "மீண்டும் முயல A",
    chapter0 = "மாலையில் கயலூர்", chapter1 = "வயல்", chapter2 = "ஆலமரக் காடு",
    chapter3 = "தாமரைக் குளம்", chapter4 = "முள்ளு மலை", chapter5 = "கோவில்",
    chapter6 = "கார்த்திகை தீபம்",
  },
}

function story.t(key, ...)
  local line = LINES[story.lang][key] or LINES.en[key] or key
  if select("#", ...) > 0 then line = string.format(line, ...) end
  return line
end

return story
