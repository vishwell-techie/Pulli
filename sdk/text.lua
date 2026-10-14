-- text.lua — placing and dressing up text, and turning numbers into it.
--
--   local text = require("text")
--
--   text.center("GAME OVER", 100, 8)          -- across the middle of the screen
--   text.right(score_text, 316, 2, 7)         -- ending at x = 316
--   text.shadow("PULLI", 140, 60, 10, 32)     -- with a dark copy behind it
--   text.outline("BOSS", 148, 20, 7, 8)       -- ringed in another colour
--   text.clock(75)          --> "1:15"
--   text.pad(7, 3)          --> "007"
--
-- Letters are 8 pixels wide and 8 tall.
--
-- text.width(s)                       Width in pixels.
-- text.center(s, y, c, middle)        Centred on x = middle (default 160).
-- text.right(s, x, y, c)              Ending at x.
-- text.shadow(s, x, y, c, shade)      With a copy one pixel down and right in
--                                     colour `shade` (default 32, black).
-- text.outline(s, x, y, c, ring)      With a ring of colour `ring` (default 32).
-- text.clock(seconds)                 "m:ss", rounded up; "h:mm:ss" past an hour.
-- text.pad(n, digits, fill)           A whole number with leading zeros, or
--                                     another fill character, to `digits` places.
-- text.wrap(s, columns)               A list of lines of at most `columns`
--                                     letters, broken at spaces where possible.
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local text = {}

function text.width(s)
  return #tostring(s) * 8
end

function text.center(s, y, c, middle)
  s = tostring(s)
  print(s, (middle or 160) - #s * 4, y, c)
end

function text.right(s, x, y, c)
  s = tostring(s)
  print(s, x - #s * 8, y, c)
end

function text.shadow(s, x, y, c, shade)
  print(s, x + 1, y + 1, shade or 32)
  print(s, x, y, c)
end

function text.outline(s, x, y, c, ring)
  ring = ring or 32
  for dy = -1, 1 do
    for dx = -1, 1 do
      if dx ~= 0 or dy ~= 0 then print(s, x + dx, y + dy, ring) end
    end
  end
  print(s, x, y, c)
end

function text.clock(seconds)
  local s = math.max(0, math.ceil(seconds))
  if s >= 3600 then
    return string.format("%d:%02d:%02d", s // 3600, s // 60 % 60, s % 60)
  end
  return string.format("%d:%02d", s // 60, s % 60)
end

function text.pad(n, digits, fill)
  local s = tostring(math.tointeger(n) or math.floor(n))
  local negative = s:sub(1, 1) == "-"
  if negative then s = s:sub(2) end
  s = string.rep(fill or "0", digits - #s - (negative and 1 or 0)) .. s
  return negative and "-" .. s or s
end

function text.wrap(s, columns)
  local lines = {}
  for paragraph in string.gmatch(tostring(s) .. "\n", "(.-)\n") do
    local line = ""
    for word in string.gmatch(paragraph, "%S+") do
      while #word > columns do
        if line ~= "" then lines[#lines + 1] = line; line = "" end
        lines[#lines + 1] = word:sub(1, columns)
        word = word:sub(columns + 1)
      end
      if line == "" then
        line = word
      elseif #line + 1 + #word <= columns then
        line = line .. " " .. word
      else
        lines[#lines + 1] = line
        line = word
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

return text
