-- dark.lua — night: the screen goes black except round the lights.
--
--   local dark = require("dark")
--   dark.clear()
--   dark.light(x, y, r)        -- a light of radius r, in screen pixels
--   dark.draw()                -- after the world, before the top bar
--
-- The lights are kept as one list, x, y, r after each other, which is what
-- shade() takes: it paints the darkness and dots the rim of every light in
-- one call.

local dark = {}
local MAX = 24 * 3                    -- 24 lights at once
local L = {}                          -- x, y, r of each light
local n = 0                           -- numbers in L that count

function dark.clear() n = 0 end

function dark.light(x, y, r)
  r = math.floor(r)
  if n >= MAX or r <= 0 or x + r < 0 or x - r >= 320 or y + r < 0 or y - r >= 240 then return end
  L[n + 1], L[n + 2], L[n + 3] = math.floor(x), math.floor(y), r
  n = n + 3
end

function dark.count() return n // 3 end

-- Whether (x, y) is inside a light.
function dark.lit(x, y)
  for i = 1, n, 3 do
    local dx, dy, r = x - L[i], y - L[i + 1], L[i + 2]
    if dx * dx + dy * dy <= r * r then return true end
  end
  return false
end

function dark.draw(colour)
  for i = n + 1, #L do L[i] = nil end   -- shade() reads the whole list
  shade(colour or 32, L, 5)
end

return dark
