-- Nizhalattam (நிழலாட்டம், "shadow play"): Pulli's platformer showcase.
--
-- A cracked clown puppet steps through the cloth screen of a shadow-puppet
-- theatre, into the world of its stories. This is step 1: Komali alone in
-- a grey test room, for tuning how he moves.
--
--   body.lua   how Komali moves: running, jumping, dodging, walls
--
-- The test room (map.tmx) has steps two to six tiles high, a stack of thin
-- floors, a pit, a pillar to slide down and gaps of growing width. SELECT
-- shows the numbers: speed, the last jump's height, and the timers.

local body = require("body")

local cam = { x = 0, y = 0 }
local show = false
local MAP_W, MAP_H = 0, 0

function init()
  local w, h = map.size()
  MAP_W, MAP_H = w * 8, h * 8
  -- the start marker on layer 1 (tile 1000), taken off the map
  local sx, sy = 40, 200
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      if map.get(1, cx, cy) == 1000 then sx, sy = cx * 8 + 4, cy * 8 + 8; map.set(1, cx, cy, 0) end
    end
  end
  body.place(sx, sy)
  cam.x = sx - 160
end

-- The camera leads the way he faces, and follows up and down more slowly,
-- catching up at once when he lands.
local function follow()
  local k = body.k
  local want_x = k.x + 5 - 160 + k.face * 40
  cam.x = cam.x + (want_x - cam.x) * 0.08
  local want_y = k.y + 10 - 140
  cam.y = cam.y + (want_y - cam.y) * (k.ground and 0.15 or 0.05)
  cam.x = math.max(0, math.min(MAP_W - 320, cam.x))
  cam.y = math.max(0, math.min(MAP_H - 240, cam.y))
end

local was_select = false
function update(dt)
  body.update(body.read())
  follow()
  local s = btn("select")
  if s and not was_select then show = not show end
  was_select = s
end

function draw()
  cls(17)
  camera(math.floor(cam.x), math.floor(cam.y))
  map.draw(0)
  body.draw()
  map.draw(1)
  camera()
  if show then
    local k, T = body.k, body.T
    rectfill(0, 0, 320, 34, 0)
    print(string.format("vx %5.2f  vy %5.2f  %s", k.vx, k.vy, k.ground and "ground" or "air " .. k.air), 4, 3, 7)
    print(string.format("last jump %.1f tiles (%d px)", k.peak / 8, math.floor(k.peak + 0.5)), 4, 13, 10)
    print(string.format("dodge %2d wait %2d  buffer %d  health %d", k.dodge, k.wait, k.buf, k.health), 4, 23, 6)
  end
end
