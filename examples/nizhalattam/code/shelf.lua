-- shelf.lua — what the box, the stall and the role picker are drawn with:
-- a panel of dark leather, and cards, each an icon (icons.lua) in a frame.
--
--   shelf.panel(title, count, icon)   the panel, its title, and what is
--                                     counted (mai or oil) at its corner
--   shelf.card(x, y, icon, lit, dim)  a card: lit when chosen, dim (a
--                                     shadow, not yet had) when not to be had
--   shelf.dots(x, y, done, of)        the steps of a repair: those done lit
--   shelf.say(s, y, c)                words under the cards, wrapped to fit
--   shelf.near(i, at, n)              left and right (and up and down) move
--                                     among n cards: the card chosen now

local text = require("text")
local C    = require("colours")
local sound = require("sound")

local shelf = {}

function shelf.panel(title, count, icon)
  rectfill(36, 40, 248, 160, C.deep)
  rect(36, 40, 248, 160, C.marigold)
  rect(38, 42, 244, 156, C.wood)
  font("small")
  print(title, 48, 48, C.lamp)
  if count then
    spr(icon, 244, 49)
    print(count, 256, 48, C.cloth)
  end
end

function shelf.card(x, y, icon, lit, dim)
  rectfill(x, y, 26, 26, lit and C.wood or C.ink)
  rect(x, y, 26, 26, lit and C.lamp or C.leather)
  if lit then rect(x - 1, y - 1, 28, 28, C.marigold) end
  if dim then for c = 1, 63 do pal(c, C.deep) end pal(C.ink, C.ink) end
  spr(icon, x + 5, y + 5, 2, 2)
  if dim then pal() end
end

function shelf.dots(x, y, done, of)
  for s = 1, of do circfill(x + s * 6 - of * 3 - 3, y, 2, s <= done and C.marigold or C.wood) end
end

-- text wrapped inside the panel's frame (48 to 276)
function shelf.say(s, y, c)
  for _, l in ipairs(text.wrap(s, 28)) do print(l, 48, y, c) y = y + 15 end
  return y
end

function shelf.near(i, at, n)
  if i.left_p or i.door then at = (at - 2) % n + 1 sound.play("select") end
  if i.right_p or i.down_p then at = at % n + 1 sound.play("select") end
  return at
end

return shelf
