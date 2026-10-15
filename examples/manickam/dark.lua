-- dark.lua — night: the screen goes black except round the lights.
--
--   local dark = require("dark")
--   dark.clear()
--   dark.light(x, y, r)        -- a light of radius r, in screen pixels
--   dark.draw()                -- after the world, before the top bar
--
-- Each row of the screen is worked out on its own: where every light
-- crosses it, joined into spans, and the gaps between the spans filled with
-- black. A ring of scattered dots softens each light's edge. Half-widths of
-- a circle are worked out once for each radius and kept, so a frame does no
-- square roots.

local dark = {}
local MAX = 24                        -- lights at once
local lx, ly, lr = {}, {}, {}
local n = 0
local widths = {}                     -- widths[r][dy] = half-width of a circle of radius r at dy
local from, to = {}, {}               -- the spans of one row
local EDGE = 4                        -- pixels of dotted edge

local function half_widths(r)
  local t = widths[r]
  if not t then
    t = {}
    for dy = 0, r do t[dy] = math.floor(math.sqrt(r * r - dy * dy)) end
    widths[r] = t
  end
  return t
end

function dark.clear() n = 0 end

function dark.light(x, y, r)
  r = math.floor(r)
  if n >= MAX or r <= 0 or x + r < 0 or x - r >= 320 or y + r < 0 or y - r >= 240 then return end
  n = n + 1
  lx[n], ly[n], lr[n] = math.floor(x), math.floor(y), r
  half_widths(r)
end

function dark.count() return n end

-- How bright it is at (x, y): 1 inside a light, 0 well outside them all.
function dark.lit(x, y)
  for i = 1, n do
    local dx, dy = x - lx[i], y - ly[i]
    if dx * dx + dy * dy <= lr[i] * lr[i] then return true end
  end
  return false
end

function dark.draw(colour)
  colour = colour or 32
  for y = 0, 239 do
    -- The spans of light on this row, sorted by where they start.
    local k = 0
    for i = 1, n do
      local dy = y - ly[i]
      if dy < 0 then dy = -dy end
      local r = lr[i]
      if dy <= r then
        local hw = widths[r][dy]
        local a, b = lx[i] - hw, lx[i] + hw
        local j = k
        while j > 0 and from[j] > a do from[j + 1], to[j + 1] = from[j], to[j]; j = j - 1 end
        from[j + 1], to[j + 1] = a, b
        k = k + 1
      end
    end
    -- Join overlapping spans, fill what lies between them, and dot the
    -- edges of each joined span.
    local x, i = 0, 1
    while i <= k do
      local a, b = from[i], to[i]
      i = i + 1
      while i <= k and from[i] <= b + 1 do
        if to[i] > b then b = to[i] end
        i = i + 1
      end
      if a > x then rectfill(x, y, a - x, 1, colour) end
      local edge = math.min(EDGE, (b - a) // 2)
      for e = a + ((a + y) & 1), a + edge, 2 do pset(e, y, colour) end
      for e = b - edge + ((b - edge + y) & 1), b, 2 do pset(e, y, colour) end
      x = b + 1
    end
    if x < 320 then rectfill(x, y, 320 - x, 1, colour) end
  end
end

return dark
