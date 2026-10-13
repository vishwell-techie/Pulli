-- hello — the smallest useful Pulli game.
-- Shows the palette, some text, and a box you can move with the d-pad.

local W, H = 320, 240
local SIZE = 16
local SPEED = 90                      -- pixels per second
local x, y = (W - SIZE) / 2, 150

function init()
  dbg("hello from Pulli")
end

function update(dt)
  if btn("left")  then x = x - SPEED * dt end
  if btn("right") then x = x + SPEED * dt end
  if btn("up")    then y = y - SPEED * dt end
  if btn("down")  then y = y + SPEED * dt end
  x = math.max(0, math.min(W - SIZE, x))
  y = math.max(96, math.min(H - SIZE - 24, y))
end

function draw()
  cls(1)
  print("HELLO FROM PULLI", 96, 16, 7)
  print("64 colours: 32 hues, 32 shadows", 36, 36, 6)

  -- the palette: every hue on top, its shadow (index + 32) right below
  for c = 0, 31 do
    rectfill(32 + c * 8, 52, 8, 12, c)
    rectfill(32 + c * 8, 64, 8, 12, c + 32)
  end
  rect(31, 51, 258, 26, 5)

  -- the box, and the same box drawn darker through pal() as its shadow
  pal(12, 12 + 32)
  rectfill(x + 3, y + 3, SIZE, SIZE, 12)
  pal()
  rectfill(x, y, SIZE, SIZE, 12)
  rect(x, y, SIZE, SIZE, 7)
  if btn("a") then print("A", x + 4, y + 4, 7) end

  print("d-pad moves the box", 84, 224, 13)
end
