-- The first Pulli cart: proves the runtime calls init/update/draw and keeps time.

local frames = 0
local elapsed = 0

function init()
  print("hello from Pulli, runtime " .. pulli.version)
end

function update(dt)
  frames = frames + 1
  elapsed = elapsed + dt
end

function draw()
  -- no screen yet, so report once a second over the console
  if frames % 30 == 0 then
    print(string.format("t=%.1fs frames=%d lua=%.1fKB", pulli.time(), frames, collectgarbage("count")))
  end
end
