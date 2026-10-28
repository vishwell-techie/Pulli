-- hello — the smallest useful Pulli game.
-- Shows the palette, some text, and a box you can move with the d-pad and
-- colour with L and R.
--
-- It uses two of the SDK's helpers: `input`, so that one press of L or R
-- changes the colour once, and `text`, to centre the words. Packing the game
-- puts them in.

local input = require("input")
local text = require("text")

local W, H = 320, 240
local SIZE = 16
local SPEED = 90                      -- pixels per second
local x, y = (W - SIZE) / 2, 150
local colour = 12                     -- one of the 32 hues; its shadow is colour + 32

function init()
  dbg("hello from Pulli")
end

function update(dt)
  input.update(dt)
  if input.pressed("l") then colour = (colour - 1) % 32 end
  if input.pressed("r") then colour = (colour + 1) % 32 end

  if btn("left")  then x = x - SPEED * dt end
  if btn("right") then x = x + SPEED * dt end
  if btn("up")    then y = y - SPEED * dt end
  if btn("down")  then y = y + SPEED * dt end
  x = math.max(0, math.min(W - SIZE, x))
  y = math.max(96, math.min(H - SIZE - 24, y))
end

function draw()
  cls(1)
  text.center("HELLO FROM PULLI", 16, 7)
  text.center("64 colours: 32 hues, 32 shadows", 36, 6)

  -- the palette: every hue on top, its shadow (index + 32) right below
  for c = 0, 31 do
    rectfill(32 + c * 8, 52, 8, 12, c)
    rectfill(32 + c * 8, 64, 8, 12, c + 32)
  end
  rect(31, 51, 258, 26, 5)
  rect(31 + colour * 8, 50, 10, 28, 7)  -- the box's colour, picked out

  -- the box, and the same box drawn darker through pal() as its shadow
  pal(colour, colour + 32)
  rectfill(x + 3, y + 3, SIZE, SIZE, colour)
  pal()
  rectfill(x, y, SIZE, SIZE, colour)
  rect(x, y, SIZE, SIZE, 7)
  if btn("a") then print("A", x + 4, y + 4, 7) end

  text.center("d-pad moves the box, L/R colour it", 224, 13)
end
