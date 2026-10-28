-- test
-- Create everything in init() and change it in place afterwards, so the
-- garbage collector has nothing to do while the game runs.

local x, y = 152, 112

function init()
end

function update(dt)
  if btn("left")  then x = x - 60 * dt end
  if btn("right") then x = x + 60 * dt end
  if btn("up")    then y = y - 60 * dt end
  if btn("down")  then y = y + 60 * dt end
end

function draw()
  cls(1)
  print("test", 8, 8, 7)
  rectfill(x, y, 16, 16, 9)
end
