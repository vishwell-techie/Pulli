-- panel.lua — the settings' panel (settings.lua): read when SELECT opens it
-- from the title or the pause, and let go when it closes.
--
--   panel.update(i, select_p)   once a frame: true once closed
--   panel.draw()
--
-- Up and down choose a row; left, right or A change it; SELECT or B close.
-- (i: body.read's buttons; up is i.door, B is i.attack.)

local settings = require("settings")
local lines = require("lines")
local text  = require("text")
local C     = require("colours")

local panel = {}
local ROWS = { "language", "music_style", "music_on", "sfx_on" }
local at = 1

function panel.update(i, select_p)
  if select_p or i.attack then return true end
  if i.door then at = (at + #ROWS - 2) % #ROWS + 1 end
  if i.down_p then at = at % #ROWS + 1 end
  if i.left_p or i.right_p or i.jump then settings.change(ROWS[at]) end
  return false
end

local function value(row)
  if row == "language" then return lines.lang == "ta" and "தமிழ்" or "English" end
  if row == "music_style" then return lines.t(settings.style()) end
  return lines.t((row == "music_on" and settings.music or row == "sfx_on" and settings.sfx) and "on" or "off")
end

function panel.draw()
  rectfill(50, 50, 220, 140, C.deep)
  rect(50, 50, 220, 140, C.marigold)
  rect(52, 52, 216, 136, C.wood)
  font()
  text.center(lines.t("settings"), 58, C.lamp)
  font("small")
  for n, row in ipairs(ROWS) do
    local y, lit = 82 + (n - 1) * 20, n == at
    if lit then rectfill(60, y - 3, 200, 15, C.wood) end
    print(lines.t(row), 70, y, lit and C.lamp or C.tan)
    local v = value(row)
    print((lit and "< " or "") .. v .. (lit and " >" or ""), 250 - text.width(v) - (lit and 18 or 0), y, lit and C.glow or C.cloth)
  end
  text.center(lines.t("settings_keys", buttons.a, buttons.select, buttons.b), 172, C.tan)
  font()
end

return panel
