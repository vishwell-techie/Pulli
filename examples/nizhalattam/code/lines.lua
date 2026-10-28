-- lines.lua — the words the game shows, in the language chosen.
--
--   local lines = require("lines")
--   lines.use("ta")                         -- or "en"
--   print(lines.t("h_move", buttons.left, buttons.right, buttons.a))
--   lines.role("Veeran")                    -- a role's name
--
-- The words are in lines_ta.lua and lines_en.lua, the same keys in both (a
-- test checks). Only the language in use is kept in memory: changing it
-- lets the other go. A story's own words (its hints) are in its rooms'
-- file (rooms_forest.lua, ...), both languages, and only while Komali is in
-- it: rooms.lua sets lines.story to them. A line may hold %s for a button's
-- icon, %d for a number.

local lines = { lang = nil, story = nil }
local L

function lines.use(lang)
  if lines.lang == lang then return end
  if lines.lang then unrequire("lines_" .. lines.lang) end
  lines.lang = lang
  L = lang == "ta" and require("lines_ta") or require("lines_en")   -- named in full, for pack
end

function lines.t(key, ...)
  local s = L[key] or (lines.story and lines.story[lines.lang][key]) or key
  if select("#", ...) > 0 then return string.format(s, ...) end
  return s
end

function lines.role(name) return L["role_" .. name] or name end

return lines
