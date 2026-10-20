-- body.lua — how Komali moves: running, jumping, dodging, sliding down walls.
--
--   local body = require("body")
--   body.place(x, y)          -- feet at (x, y), in map pixels
--   body.update(input)        -- once a frame; input from body.read()
--   body.hurt(n, from_x)      -- struck: false if he could not be touched
--   body.draw(c)              -- c: the role's colours, swapped in (pal)
--
-- Every number that decides how it feels is in body.T, in pixels and
-- frames (the game runs at a fixed 60 frames a second), so it can be tuned
-- in one place. Walls are tiles with flag 1; thin floors have flag 2: they
-- hold Komali up from above, and down + A drops him through.

local move = require("move")

local body = {}

local T = {
  run = 1.6,          -- top running speed, pixels a frame (96 a second)
  accel = 0.4,        -- on the ground: full speed in 4 frames
  stop = 0.55,        --   and stopped in 3
  air_accel = 0.3,    -- in the air: a little less grip
  air_stop = 0.2,
  jump = 3.7,         -- the jump's starting speed: 36 px (4.5 tiles) held
  rise = 0.18,        -- gravity while rising with A held
  fall = 0.3,         -- gravity falling, or rising with A let go: snappier
  cut = 2.5,          -- letting go of A caps the climb: a tap rises 1.5 tiles
  max_fall = 5,
  coyote = 6,         -- frames after leaving a ledge he can still jump
  buffer = 6,         -- frames A is remembered before landing
  dodge = 18,         -- frames a dodge lasts
  dodge_safe = { 2, 11 },  -- the frames of it he cannot be touched (10)
  dodge_speed = 3.2,
  dodge_wait = 30,    -- frames after a dodge before the next
  slide = 1.0,        -- falling speed against a wall
  drop = 12,          -- frames thin floors are ignored after down + A
  pit = 10,           -- health a fall into a pit costs
  struck = 60,        -- frames he cannot be touched after a blow
  thrown = 2.2,       -- how hard a blow throws him back
}
body.T = T

local SOLID, THIN = 1, 2
-- Sprites (cell x + 64 * cell y), 16x24 each.
local IDLE, RUN, JUMP, FALL, DODGE, WALL = 256, 260, 268, 270, 272, 276

-- Komali: his box is 10x20, his feet at (x + 5, y + 20).
local k = { x = 0, y = 0, w = 10, h = 20, vx = 0, vy = 0, face = 1,
            ground = false, air = 0, buf = 0, dodge = 0, wait = 0, drop = 0,
            wall = 0, health = 100, safe_x = 0, safe_y = 0, step = 0,
            peak = 0, top = 0, from = 0,
            slow = 1,          -- how fast he may run while striking (set by fight.lua)
            dodge_wait = 1,    -- how long he waits between dodges (his own role: half)
            struck = 0, guard = 0 }
body.k = k

move.solid, move.edges = SOLID, false

function body.place(x, y)
  k.x, k.y, k.vx, k.vy = x - 5, y - k.h, 0, 0
  k.safe_x, k.safe_y, k.dodge, k.wait = k.x, k.y, 0, 0
end

-- The buttons this frame. Kept apart from the moving, so tests and the
-- benchmark can drive Komali without the pad.
local was = {}
local function pressed(b)
  local now = btn(b)
  local p = now and not was[b]
  was[b] = now
  return p
end
local I = {}            -- filled in afresh each frame, never made again
function body.read()
  I.left, I.right, I.down, I.up = btn("left"), btn("right"), btn("down"), btn("up")
  I.a, I.b = btn("a"), btn("b")
  I.jump, I.dodge, I.attack, I.skill = pressed("a"), pressed("y"), pressed("b"), pressed("x")
  I.swap = (pressed("r") and 1 or 0) - (pressed("l") and 1 or 0)
  I.door = pressed("up")                -- up at a door goes through it
  return I
end

local function flags_at(cx, cy) return map.flags(map.get(0, cx, cy)) end

-- A thin floor right under his feet?
local function on_thin()
  local feet = k.y + k.h
  if feet % 8 ~= 0 or k.drop > 0 then return false end
  local cy = feet // 8
  for cx = math.floor(k.x) // 8, math.floor(k.x + k.w - 1) // 8 do
    if flags_at(cx, cy) & THIN ~= 0 then return true end
  end
  return false
end

-- Falling by dy: the first thin floor his feet would pass, if any.
local function thin_below(dy)
  if dy <= 0 or k.drop > 0 then return nil end
  local feet = k.y + k.h
  for cy = math.ceil(feet / 8), (feet + dy) // 8 do
    if cy * 8 >= feet then
      for cx = math.floor(k.x) // 8, math.floor(k.x + k.w - 1) // 8 do
        if flags_at(cx, cy) & THIN ~= 0 then return cy * 8 end
      end
    end
  end
end

local function toward(v, goal, by)
  if v < goal then return math.min(goal, v + by) end
  return math.max(goal, v - by)
end

function body.update(i)
  local was_ground = k.ground
  if k.wait > 0 then k.wait = k.wait - 1 end
  if k.struck > 0 then k.struck = k.struck - 1 end
  if k.drop > 0 then k.drop = k.drop - 1 end
  k.buf = i.jump and T.buffer or math.max(0, k.buf - 1)

  local dir = (i.right and 1 or 0) - (i.left and 1 or 0)
  if k.struck > T.struck - 12 then dir = 0 end      -- thrown back: no steering yet
  if dir ~= 0 and k.dodge == 0 and k.slow == 1 then k.face = dir end

  -- the dodge: a quick roll, straight ahead, gravity held off
  if i.dodge and k.dodge == 0 and k.wait == 0 then
    k.dodge, k.vy = T.dodge, 0
  end
  if k.dodge > 0 then
    k.dodge = k.dodge - 1
    k.vx = k.face * T.dodge_speed
    if k.dodge == 0 then k.wait, k.vx = math.floor(T.dodge_wait * k.dodge_wait), k.face * T.run end
  else
    local grip = k.ground and (dir ~= 0 and T.accel or T.stop) or (dir ~= 0 and T.air_accel or T.air_stop)
    k.vx = toward(k.vx, dir * T.run * k.slow, grip)
    -- jumping: on the ground, or just off it; down + A on a thin floor drops
    if k.buf > 0 and (k.ground or k.air <= T.coyote) then
      if i.down and k.ground and on_thin() then
        k.drop, k.buf = T.drop, 0
      else
        k.vy, k.buf, k.ground, k.air = -T.jump, 0, false, T.coyote + 1
        k.from, k.top = k.y, k.y
      end
    end
    if k.ground and k.vy >= 0 then
      k.vy = 0                                   -- standing: no falling
    else
      local g = (k.vy < 0 and i.a) and T.rise or T.fall
      if k.vy < 0 and not i.a and k.vy < -T.cut then k.vy = -T.cut end
      k.vy = math.min(k.vy + g, T.max_fall)
    end
  end

  -- against a wall, falling, pressing into it: slide slowly
  k.wall = 0
  if not k.ground and k.dodge == 0 and dir ~= 0 and k.vy > 0
     and move.blocked(k.x + dir, k.y, k.w, k.h) then
    k.wall, k.vy = dir, math.min(k.vy, T.slide)
  end

  -- move: across, then down, landing on thin floors from above
  local dy = k.vy
  local land = thin_below(dy)
  if land then dy = land - (k.y + k.h) end
  local hit_x, hit_y = move.by(k, k.vx, dy)
  if hit_x then k.vx = 0 end
  if land and math.abs(k.y + k.h - land) < 0.01 then k.y, k.vy = land - k.h, 0 end
  if hit_y then
    if k.vy > 0 then k.y = math.floor(k.y) end       -- feet on a whole pixel
    k.vy = 0
  end
  k.ground = move.blocked(k.x, k.y + k.h, k.w, 1) or on_thin()
  if was_ground and not k.ground and k.vy >= 0 then k.from, k.top = k.y, k.y end   -- walked off
  if k.ground then
    k.air = 0
    if not was_ground then k.peak = k.from - k.top end   -- how high the last jump rose
    -- a safe place to come back to: firm ground under him and a tile
    -- either side, so he does not come back on the very edge of the pit
    local feet = k.y + k.h
    if move.blocked(k.x - 8, feet, 1, 1) and move.blocked(k.x, feet, 1, 1)
       and move.blocked(k.x + k.w - 1, feet, 1, 1) and move.blocked(k.x + k.w + 7, feet, 1, 1) then
      k.safe_x, k.safe_y = k.x, k.y
    end
  else
    k.air = k.air + 1
    k.top = math.min(k.top, k.y)
  end
  -- into a pit: back on the last safe ledge, a little hurt
  local _, mh = map.size()
  if k.y > mh * 8 + 16 then
    k.health = math.max(1, k.health - T.pit)
    k.x, k.y, k.vx, k.vy, k.dodge = k.safe_x, k.safe_y, 0, 0, 0
  end
  k.step = k.step + math.abs(k.vx)
end

-- Can he be touched this frame? Not in the heart of a dodge, nor just
-- after a blow.
function body.safe()
  local f = T.dodge - k.dodge
  return k.struck > 0 or (k.dodge > 0 and f >= T.dodge_safe[1] and f <= T.dodge_safe[2])
end

-- A blow of n from the side of from_x. k.guard, set by fight.lua, takes
-- off part of every blow (the warrior's), or all of one from the front
-- (a shield). Returns how much it cost, or false if it did not land.
function body.hurt(n, from_x)
  if body.safe() then return false end
  local side = from_x < k.x + k.w / 2 and -1 or 1
  if k.guard < 0 and side == k.face then return false end   -- shield up, facing it
  n = math.max(1, math.floor(n * (1 - math.max(0, k.guard)) + 0.5))
  k.health = math.max(0, k.health - n)
  k.struck, k.dodge = T.struck, 0
  k.vx, k.vy, k.ground = -side * T.thrown, -1.6, false
  return n
end

function body.draw(c)
  local s
  if k.dodge > 0 then s = DODGE + (k.dodge // 3 % 2) * 2
  elseif k.wall ~= 0 then s = WALL
  elseif not k.ground then s = k.vy < 0 and JUMP or FALL
  elseif math.abs(k.vx) > 0.2 then s = RUN + (k.step // 10 % 4) * 2
  else s = IDLE + (stat("frame") // 40 % 2) * 2 end
  local flip = k.face < 0
  if k.wall ~= 0 then flip = k.wall > 0 end
  if k.struck > 0 and k.struck // 4 % 2 == 0 then return end   -- flashing after a blow
  if c then for n = 1, #c, 2 do pal(c[n], c[n + 1]) end end
  spr(s, math.floor(k.x) - 3, math.floor(k.y) - 2, 2, 3, flip)
  pal()
end

return body
