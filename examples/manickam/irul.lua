-- irul.lua — Irul, the shadow serpent: a head and a chain of segments that
-- follow the path the head has taken.
--
--   local irul = require("irul")
--   local snake = irul.new(16, 6, x, y)   -- 16 segments, 6 frames of trail apart
--   snake:go(x, y)                        -- move the head; call once a frame
--   snake.scale = 0.5                     -- smaller, drawn with sspr()
--   snake:draw()
--
-- The head's last positions are kept in a ring; segment i is drawn where the
-- head was i * gap frames ago. Every segment is a sprite of its own, so a
-- long Irul is a good test of how many sprites a frame can take.

local irul = {}
irul.__index = irul

-- Where the head, body and tail are on the sheet, in pixels.
local HEAD_X, BODY_X, TAIL_X, ROW_Y = 416, 432, 448, 80

function irul.new(n, gap, x, y)
  local s = setmetatable({ n = n, gap = gap, scale = 1, x = x, y = y, hx = {}, hy = {}, at = 1,
                           show = true, shade = 0 }, irul)
  s.size = n * gap + 1
  for i = 1, s.size do s.hx[i], s.hy[i] = x, y end
  return s
end

-- Put the head at (x, y), and remember where it was.
function irul:go(x, y)
  self.x, self.y = x, y
  self.at = self.at % self.size + 1
  self.hx[self.at], self.hy[self.at] = x, y
end

-- Where segment i (0 is the head) is now.
function irul:segment(i)
  local k = (self.at - 1 - i * self.gap) % self.size + 1
  return self.hx[k], self.hy[k]
end

local function piece(sx, x, y, s)
  local d = 16 * s
  sspr(sx, ROW_Y, 16, 16, x - d / 2, y - d / 2, d, d)
end

function irul:draw()
  if not self.show then return end
  local s = self.scale
  for i = self.n, 1, -1 do
    local x, y = self:segment(i)
    -- the body thins towards the tail
    local k = s * (0.6 + 0.4 * (1 - i / self.n))
    piece(i == self.n and TAIL_X or BODY_X, x, y, k)
  end
  piece(HEAD_X, self.x, self.y, s * 1.1)
end

return irul
