-- pong — the API's first real test.
--
-- Written to the SDK house style: no table allocation inside update() or
-- draw(). Every object is created once in init() and mutated in place, so
-- the garbage collector has nothing to do during play. This is the pattern
-- every Pulli game should follow (see SPEC §0.4).

local W, H = 320, 240
local PAD_W, PAD_H = 4, 36
local SPEED = 150

local player, ai, ball, score, best, shake

function init()
  player = { x = 8,        y = H/2 - PAD_H/2 }
  ai     = { x = W - 12,   y = H/2 - PAD_H/2 }
  ball   = { x = W/2, y = H/2, vx = SPEED, vy = SPEED * 0.6, r = 3 }
  score  = 0
  shake  = 0
  best   = load("best", 0)
end

local function reset_ball(dir)
  ball.x, ball.y = W/2, H/2
  ball.vx = SPEED * dir
  ball.vy = SPEED * 0.6 * (math.random() < 0.5 and -1 or 1)
end

function update(dt)
  -- player
  if btn("up")   then player.y = player.y - SPEED * dt end
  if btn("down") then player.y = player.y + SPEED * dt end
  player.y = math.max(0, math.min(H - PAD_H, player.y))

  -- ai: deliberately imperfect, tracks the ball with a lag
  local target = ball.y - PAD_H/2
  ai.y = ai.y + (target - ai.y) * math.min(1, 2.5 * dt)
  ai.y = math.max(0, math.min(H - PAD_H, ai.y))

  -- ball
  ball.x = ball.x + ball.vx * dt
  ball.y = ball.y + ball.vy * dt
  if ball.y < ball.r then ball.y = ball.r; ball.vy = -ball.vy end
  if ball.y > H - ball.r then ball.y = H - ball.r; ball.vy = -ball.vy end

  -- paddle collisions
  if ball.vx < 0 and ball.x - ball.r < player.x + PAD_W
     and ball.y > player.y and ball.y < player.y + PAD_H then
    ball.vx = -ball.vx * 1.05
    ball.vy = ball.vy + (ball.y - (player.y + PAD_H/2)) * 2
    score = score + 1
    shake = 0.1
    sfx(0)
  end
  if ball.vx > 0 and ball.x + ball.r > ai.x
     and ball.y > ai.y and ball.y < ai.y + PAD_H then
    ball.vx = -ball.vx
    sfx(1)
  end

  -- scoring
  if ball.x < -10 then
    if score > best then best = score; save("best", best) end
    score = 0
    reset_ball(1)
  elseif ball.x > W + 10 then
    score = score + 5
    reset_ball(-1)
  end

  if shake > 0 then shake = shake - dt end
end

function draw()
  cls(0)

  -- screen shake via camera, costs nothing
  if shake > 0 then
    camera(math.random(-2, 2), math.random(-2, 2))
  else
    camera(0, 0)
  end

  -- centre net
  for y = 0, H, 12 do
    rectfill(W/2 - 1, y, 2, 6, 5)
  end

  rectfill(player.x, player.y, PAD_W, PAD_H, 12)
  rectfill(ai.x,     ai.y,     PAD_W, PAD_H, 8)
  circfill(ball.x,   ball.y,   ball.r,       7)

  camera(0, 0)
  print("SCORE " .. score, 8, 8, 7)
  print("BEST " .. best, W - 80, 8, 6)
end
