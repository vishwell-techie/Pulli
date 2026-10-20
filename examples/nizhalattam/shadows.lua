-- shadows.lua — the enemies: shadows of ink and paper. Step 2 has one, the
-- cut-paper soldier.
--
--   shadows.add(x, y)         a soldier, feet at (x, y)
--   shadows.update(body)      once a frame; strikes Komali through body.hurt
--   shadows.strike(s, n, dir, heavy)   Komali's blow: "hit", "blocked",
--                             "torn", or nil if it could not land
--   shadows.draw()
--
-- The soldier walks up to Komali and holds his guard to the front, so a
-- light blow from the front is turned aside; one from behind lands, and
-- so does a heavy one (the warrior's charged slash, a swap strike). When
-- close he winds up (leaning back, flashing at the end), strikes, and
-- rests a moment: that rest, and his wind-up, are the time to hit him.
-- Beaten, he tears into scraps and leaves drops of ink (mai).

local move = require("move")
local fx   = require("fx")

local shadows = { list = {}, hits = 0 }

local S = {
  hp = 40,
  speed = 0.6,         -- walking, pixels a frame
  sight = 120,         -- how far off he sees Komali
  reach = 22,          -- how close he comes before winding up
  wind = 24,           -- frames of wind-up: the warning
  strike = 6,          -- frames the blow can land
  rest = 40,           -- frames after it, open to blows
  reel = 14,           -- frames knocked back by a blow that lands
  blow = 12,           -- what his blow costs Komali
  mai = { 1, 5 },      -- drops of ink he leaves
}
shadows.S = S

-- Sprites (16x24): standing, walking, winding up, striking, struck.
local STAND, WALK, WIND, STRIKE, REEL = 448, 450, 452, 454, 456

function shadows.add(x, y)
  local s = { x = x - 5, y = y - 20, w = 10, h = 20, vx = 0, vy = 0, face = -1,
              hp = S.hp, state = "walk", t = 0, landed = false, hit = 0, on = true, step = 0 }
  shadows.list[#shadows.list + 1] = s
  return s
end

function shadows.clear()
  for n = #shadows.list, 1, -1 do shadows.list[n] = nil end
end

local function overlap(ax, ay, aw, ah, b)
  return ax < b.x + b.w and b.x < ax + aw and ay < b.y + b.h and b.y < ay + ah
end
shadows.overlap = overlap

function shadows.update(body)
  local k = body.k
  local kx = k.x + k.w / 2
  for _, s in ipairs(shadows.list) do
    if s.on and math.abs(s.x - k.x) < 360 then        -- those far off sleep
      local dx = kx - (s.x + s.w / 2)
      local st = s.state
      if st == "walk" then
        if math.abs(dx) < S.sight and math.abs(k.y - s.y) < 40 then
          s.face = dx < 0 and -1 or 1
          if math.abs(dx) > S.reach then
            -- walk on, but not off an edge
            local ahead = s.face > 0 and s.x + s.w + 1 or s.x - 2
            s.vx = move.blocked(ahead, s.y + s.h, 1, 1) and s.face * S.speed or 0
          else
            s.vx, s.state, s.t = 0, "wind", S.wind
          end
        else
          s.vx = 0
        end
      elseif st == "wind" then
        s.t = s.t - 1
        if s.t <= 0 then s.state, s.t, s.landed = "strike", S.strike, false end
      elseif st == "strike" then
        local bx = s.face > 0 and s.x + s.w or s.x - 18
        if not s.landed and overlap(bx, s.y + 4, 18, 12, k) then
          if body.hurt(S.blow, s.x + s.w / 2) then
            s.landed = true
            shadows.hits = shadows.hits + 1
          end
        end
        s.t = s.t - 1
        if s.t <= 0 then s.state, s.t = "rest", S.rest end
      elseif st == "rest" or st == "reel" then
        s.t = s.t - 1
        if s.t <= 0 then s.state = "walk" end
      end
      if st ~= "walk" then s.vx = s.vx * 0.85 end
      s.vy = math.min(s.vy + 0.3, 5)
      local _, hy = move.by(s, s.vx, s.vy)
      if hy then s.vy = 0 end
      s.step = s.step + math.abs(s.vx)
    end
  end
end

function shadows.strike(s, n, dir, heavy)
  if not s.on then return nil end
  -- a light blow from the side he faces, while he is on guard, is turned aside
  if not heavy and s.state == "walk" and dir == -s.face then
    fx.spark(s.x + s.w / 2 + s.face * 6, s.y + 10)
    s.vx = -s.face * 0.8
    return "blocked"
  end
  s.hp = s.hp - n
  if s.hp <= 0 then
    s.on = false
    fx.tear(s.x + s.w / 2, s.y + s.h / 2, math.random(S.mai[1], S.mai[2]))
    return "torn"
  end
  -- a heavy blow breaks his wind-up; a light one lands, but he strikes anyway
  if heavy or s.state == "walk" or s.state == "rest" then
    s.state, s.t = "reel", heavy and S.reel * 2 or S.reel
  end
  s.vx = dir * (heavy and 3 or 1.5)
  return "hit"
end

function shadows.draw()
  for _, s in ipairs(shadows.list) do
    if s.on then
      local x, y, st = math.floor(s.x) - 3, math.floor(s.y) - 4, s.state
      local n = st == "wind" and WIND or st == "strike" and STRIKE or st == "reel" and REEL
                or (math.abs(s.vx) > 0.1 and (s.step // 8 % 2 == 0 and WALK or STAND)) or STAND
      if st == "wind" and s.t < 8 and s.t % 2 == 0 then pal(15, 7) pal(31, 7) end   -- about to strike
      spr(n, x, y, 2, 3, s.face < 0)
      pal()
      -- his sword: at his side, raised behind, or out in front
      local hx, hy = x + 8 + s.face * 5, y + 13
      if st == "wind" then line(hx, hy, hx - s.face * 6, hy - 11, 6)
      elseif st == "strike" then line(hx, hy, hx + s.face * 16, hy - 1, 7)
      else line(hx, hy, hx + s.face * 3, hy + 9, 6) end
    end
  end
end

return shadows
