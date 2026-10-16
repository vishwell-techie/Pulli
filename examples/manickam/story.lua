-- story.lua — every word the game shows, in Tamil and in English.
--
--   local story = require("story")
--   story.lang = "en"                  -- or "ta"
--   print(story.t("new_game"), 8, 8, 7)
--   story.name("paati")                -- a speaker's name: "Paati" or "பாட்டி"
--
-- The words themselves are in lines_ta.lua and lines_en.lua, each one long
-- string of "key=words" lines, searched when a line is wanted. Only the
-- language in use is loaded; the other is loaded the first time the player
-- switches to it. A key missing from Tamil falls back to English, then to
-- the key itself, so a missing line shows up as its name.
--
-- Tamil takes three bytes a letter in UTF-8, and Lua memory is short, so
-- once loaded every Tamil line is packed to one byte a letter: the Tamil
-- block, U+0B80 to U+0BFF, becomes bytes 128 to 255, and English stays as
-- it is. A line is unpacked when it is shown; the lines of menus and the
-- top bar, shown every frame, are unpacked once and kept.

local story = { lang = "ta" }
local loaded, kept, nkept = {}, {}, 0

local function pack(s)
  return (s:gsub("\224[\174\175][\128-\191]", function(c)
    local b2, b3 = c:byte(2, 3)
    return string.char(128 + (b2 - 174) * 64 + (b3 - 128))
  end))
end

local function unpack_ta(c)
  local n = c:byte() - 128
  return string.char(224, 174 + n // 64, 128 + n % 64)
end

local function lines(lang)
  local t = loaded[lang]
  if not t then
    local file = lang == "ta" and require("lines_ta") or require("lines_en")
    t = "\n" .. (lang == "ta" and pack(file[1]) or file[1])
    file[1] = nil                       -- the module's own copy can go
    loaded[lang] = t
  end
  return t
end

local function find(lang, key)
  local line = lines(lang):match("\n" .. key .. "=([^\n]*)")
  if line then
    if lang == "ta" then line = line:gsub("[\128-\255]", unpack_ta) end
    line = line:gsub("\\n", "\n")
  end
  return line
end

function story.t(key, ...)
  local lang = story.lang
  local line = kept[lang .. key]
  if not line then
    line = find(lang, key) or lang ~= "en" and find("en", key) or key
    if select("#", ...) == 0 and #line < 64 then
      if nkept > 30 then kept, nkept = {}, 0 end
      kept[lang .. key], nkept = line, nkept + 1
    end
  end
  if select("#", ...) > 0 then line = string.format(line, ...) end
  return line
end

function story.name(who)
  return story.t("who_" .. who)
end

return story
