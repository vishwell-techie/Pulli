-- settings.lua — the game's settings: the language, the music's style
-- (Carnatic or Western, whatever the language), the music on or off, the
-- sound effects on or off. They are the console's, not a slot's, and kept
-- (save "settings"; the language is run.language's own). Changed in a
-- panel SELECT opens from the title and from the pause (panel.lua, read
-- only while it is open).
--
--   settings.load()               at the start: what was kept
--   settings.style()              "carnatic" or "western": the one chosen, or,
--                                 until one is, Carnatic in Tamil and Western
--                                 in English
--   settings.music, settings.sfx  on (true) or off
--   settings.change(row)          "language", "music_style", "music_on" or
--                                 "sfx_on" changed, kept, and settings.changed
--                                 told (rooms.lua: the music, the sound)
--   settings.open(), settings.shown, settings.update(i, select_p) (true once
--                                 closed), settings.draw()   the panel

local run   = require("run")
local lines = require("lines")

local settings = { music = true, sfx = true, chosen = nil, shown = false, changed = function() end }

function settings.load()
  local s = load("settings")
  if type(s) ~= "table" then s = {} end
  settings.chosen = (s.style == "carnatic" or s.style == "western") and s.style or nil
  settings.music = s.music ~= false
  settings.sfx = s.sfx ~= false
end

function settings.style()
  return settings.chosen or (run.language() == "ta" and "carnatic" or "western")
end

function settings.change(row)
  if row == "language" then run.set_language(lines.lang == "ta" and "en" or "ta")
  elseif row == "music_style" then settings.chosen = settings.style() == "carnatic" and "western" or "carnatic"
  elseif row == "music_on" then settings.music = not settings.music
  elseif row == "sfx_on" then settings.sfx = not settings.sfx end
  save("settings", { style = settings.chosen, music = settings.music, sfx = settings.sfx })
  save_commit()
  settings.changed(row)
end

function settings.open() settings.shown = true end
function settings.update(i, select_p)
  if not require("panel").update(i, select_p) then return false end
  settings.shown = false
  unrequire("panel")
  return true
end
function settings.draw() require("panel").draw() end

return settings
