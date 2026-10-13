-- pong — first to seven, against the console or a second player.
--
-- Written to the SDK house style: no table allocation inside update() or
-- draw(). Every object is created once in init() and mutated in place, so
-- the garbage collector has nothing to do during play. This is the pattern
-- every Pulli game should follow (see SPEC §0.4).

local W, H = 320, 240
local PAD_W, PAD_H = 4, 36
local PAD_SPEED = 170               -- a player's paddle, pixels per second

-- How well the console plays at each level:
--   speed   its paddle, pixels per second (a player's is PAD_SPEED)
--   react   it only reads the ball past this fraction of the court
--   err     how far off-centre it aims, in pixels, at the slowest ball
--   tire    how much worse that gets by the time the ball is at full speed
--   top     the fastest the ball gets, pixels per second
-- A paddle reaches 21 pixels from its centre, so err + tire above 21 means
-- the console starts to miss once a rally is fast. Every level gets there:
-- that is what ends a rally between two good players.
local LEVELS = {
  { name = "EASY",   speed = 95,  react = 0.55, err = 12, tire = 22,   top = 330 },
  { name = "NORMAL", speed = 125, react = 0.40, err = 6,  tire = 20,   top = 330 },
  { name = "HARD",   speed = 150, react = 0.25, err = 4,  tire = 20,   top = 330 },
  { name = "INSANE", speed = 185, react = 0,    err = 2,  tire = 20.5, top = 390 },
}
local BALL_SPEED = 150              -- at the serve; LEVELS sets the top speed
local R = 3                         -- ball radius
local WIN = 7                       -- points needed to win the match
local SERVE_DELAY = 0.8
local TOP_SPEED_2P = 330            -- two-player matches ignore the level
local MIN_ANGLE = 0.12              -- a return is never perfectly flat
local TARGET_TEXT = "FIRST TO " .. WIN .. " WINS"

local state                         -- "menu", "serve", "play" or "over"
local paused                        -- only ever true during "serve" or "play"
local a_was_down                    -- to tell a new press of A from a held one
local players                       -- 1: against the console, 2: two people
local left, right, ball
local level                         -- index into LEVELS, kept between runs
local ai_aim, timer, shake, wins, wins_text, level_text, result

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function centre(text, y, c)
  print(text, (W - #text * 8) / 2, y, c)
end

local function set_score(p, n)
  p.score = n
  p.text = tostring(n)              -- built here, not every frame in draw()
end

-- The console aims a little off the centre of its paddle, and further off
-- the faster the ball is going, so long rallies end in a mistake.
local function aim_ai()
  local l = LEVELS[level]
  local err = l.err + l.tire * (ball.speed - BALL_SPEED) / (l.top - BALL_SPEED)
  ai_aim = (math.random() * 2 - 1) * err
end

local function serve(dir)
  ball.x, ball.y = W / 2, H / 2
  ball.speed = BALL_SPEED
  ball.vx = BALL_SPEED * dir
  ball.vy = BALL_SPEED * 0.5 * (math.random() < 0.5 and -1 or 1)
  aim_ai()
  timer = SERVE_DELAY
  state = "serve"
end

-- Menu text is rebuilt only when the level or the win count changes.
local function set_level(n)
  level = (n - 1) % #LEVELS + 1
  level_text = "LEVEL: < " .. LEVELS[level].name .. " >"
  wins_text = "WINS ON " .. LEVELS[level].name .. ": " .. wins[level]
end

local function start_match()
  set_score(left, 0)
  set_score(right, 0)
  left.y, right.y = H / 2 - PAD_H / 2, H / 2 - PAD_H / 2
  serve(math.random() < 0.5 and -1 or 1)
end

function init()
  left  = { x = 8,      y = H / 2 - PAD_H / 2, score = 0, text = "0" }
  right = { x = W - 12, y = H / 2 - PAD_H / 2, score = 0, text = "0" }
  ball  = { x = W / 2, y = H / 2, vx = 0, vy = 0, speed = BALL_SPEED }
  players, ai_aim, timer, shake = 1, 0, 0, 0
  wins = {}
  for i = 1, #LEVELS do wins[i] = load("wins" .. i, 0) end
  set_level(load("level", 2))
  result = ""
  paused = false
  a_was_down = false
  state = "menu"
end

-- The second player's two inputs. Both players share one console today:
-- player 2 uses X and B. When consoles can be linked, this is the one place
-- that changes, to read the other console's up and down instead.
local function p2_up()   return btn("x") end
local function p2_down() return btn("b") end

-- Where the ball will be when it reaches horizontal position x, allowing
-- for bounces off the top and bottom walls.
local function predict(x)
  local t = (x - ball.x) / ball.vx
  local span = H - 2 * R
  local p = (ball.y - R + ball.vy * t) % (2 * span)
  if p > span then p = 2 * span - p end
  return p + R
end

local function move_ai(dt)
  local target = H / 2
  local l = LEVELS[level]
  if ball.vx > 0 and ball.x > W * l.react then target = predict(right.x - R) + ai_aim end
  local step = l.speed * dt
  right.y = clamp(right.y + clamp(target - PAD_H / 2 - right.y, -step, step), 0, H - PAD_H)
end

local function move_paddles(dt)
  if btn("up")   then left.y = left.y - PAD_SPEED * dt end
  if btn("down") then left.y = left.y + PAD_SPEED * dt end
  left.y = clamp(left.y, 0, H - PAD_H)

  if players == 1 then
    move_ai(dt)
  else
    if p2_up()   then right.y = right.y - PAD_SPEED * dt end
    if p2_down() then right.y = right.y + PAD_SPEED * dt end
    right.y = clamp(right.y, 0, H - PAD_H)
  end
end

-- Send the ball back from paddle p. Where it struck the paddle sets the
-- angle, and every return is a little faster than the last.
local function bounce(p, dir, face)
  local off = clamp((ball.y - (p.y + PAD_H / 2)) / (PAD_H / 2), -1, 1)
  -- A dead-centre hit would send the ball back level, and two still paddles
  -- would then rally for ever. Keep some of the slope it arrived with.
  if off > -MIN_ANGLE and off < MIN_ANGLE then
    off = ball.vy < 0 and -MIN_ANGLE or MIN_ANGLE
  end
  local top = players == 1 and LEVELS[level].top or TOP_SPEED_2P
  ball.speed = math.min(ball.speed * 1.06, top)
  ball.vx = ball.speed * dir
  ball.vy = ball.speed * 0.8 * off
  ball.x = face + R * dir
  shake = 0.1
  if dir > 0 then
    aim_ai()
    sfx(0)
  else
    sfx(1)
  end
end

local function point_to(winner, loser_dir)
  set_score(winner, winner.score + 1)
  sfx(2)
  if winner.score < WIN then
    serve(loser_dir)
    return
  end
  state = "over"
  if players == 2 then
    result = winner == left and "PLAYER 1 WINS" or "PLAYER 2 WINS"
  elseif winner == left then
    result = "YOU WIN"
    wins[level] = wins[level] + 1
    save("wins" .. level, wins[level])
    set_level(level)
  else
    result = "THE CONSOLE WINS"
  end
end

local function move_ball(dt)
  local before = ball.x
  ball.x = ball.x + ball.vx * dt
  ball.y = ball.y + ball.vy * dt
  if ball.y < R then ball.y = R; ball.vy = -ball.vy end
  if ball.y > H - R then ball.y = H - R; ball.vy = -ball.vy end

  -- A paddle returns the ball only if the ball crossed its face this frame,
  -- so a fast ball cannot pass through and a ball already behind is lost.
  local face = left.x + PAD_W
  if ball.vx < 0 and before - R >= face and ball.x - R < face
     and ball.y > left.y - R and ball.y < left.y + PAD_H + R then
    bounce(left, 1, face)
  end
  face = right.x
  if ball.vx > 0 and before + R <= face and ball.x + R > face
     and ball.y > right.y - R and ball.y < right.y + PAD_H + R then
    bounce(right, -1, face)
  end

  if ball.x < -10 then
    point_to(right, -1)
  elseif ball.x > W + 10 then
    point_to(left, 1)
  end
end

function update(dt)
  -- btnp("a") repeats while A is held, which suits scrolling but not
  -- confirming: one long press must not start a match and then skip the
  -- result. So A counts here only when it has been let go in between.
  local a_down = btn("a")
  local confirm = (a_down and not a_was_down) or btnp("start")
  a_was_down = a_down

  -- START pauses a match and resumes it; while paused, SELECT gives up.
  if state == "serve" or state == "play" then
    if btnp("start") then paused = not paused end
    if paused then
      if btnp("select") then paused = false; state = "menu" end
      return
    end
  end

  if shake > 0 then shake = shake - dt end

  if state == "menu" then
    if btnp("up") or btnp("down") then players = 3 - players end
    if players == 1 then
      if btnp("left")  then set_level(level - 1) end
      if btnp("right") then set_level(level + 1) end
    end
    if confirm then
      -- The runtime starts every game with the same random sequence. How
      -- long the player took to press the button makes each match differ.
      math.randomseed(stat("frame"))
      save("level", level)
      start_match()
    end
  elseif state == "serve" then
    move_paddles(dt)
    timer = timer - dt
    if timer <= 0 then state = "play" end
  elseif state == "play" then
    move_paddles(dt)
    move_ball(dt)
  elseif confirm then
    state = "menu"
  end
end

function draw()
  cls(0)

  -- screen shake via camera, costs nothing
  if shake > 0 and not paused then
    camera(math.random(-2, 2), math.random(-2, 2))
  else
    camera(0, 0)
  end

  -- centre net
  for y = 0, H, 12 do
    rectfill(W / 2 - 1, y, 2, 6, 5)
  end

  rectfill(left.x,  left.y,  PAD_W, PAD_H, 12)
  rectfill(right.x, right.y, PAD_W, PAD_H, 8)
  if state == "serve" or state == "play" then
    circfill(ball.x, ball.y, R, 7)
  end

  camera(0, 0)
  if state ~= "menu" then
    print(left.text,  W / 2 - 16 - #left.text * 8, 8, 12)
    print(right.text, W / 2 + 16, 8, 8)
  end

  if state == "menu" then
    rectfill(40, 48, 240, 168, 1)
    rect(40, 48, 240, 168, 6)
    centre("P O N G", 60, 7)
    centre(TARGET_TEXT, 76, 6)
    centre(players == 1 and "> 1 PLAYER <" or "1 PLAYER", 98, players == 1 and 10 or 13)
    centre(players == 2 and "> 2 PLAYERS <" or "2 PLAYERS", 112, players == 2 and 10 or 13)
    if players == 1 then
      centre(level_text, 132, 9)
      centre("LEFT/RIGHT CHANGE THE LEVEL", 146, 6)
      centre(wins_text, 180, 13)
    else
      centre("P1: UP/DOWN   P2: X/B", 139, 6)
    end
    centre("PRESS A TO START", 164, 7)
    centre("START PAUSES A MATCH", 200, 5)
  elseif paused then
    rectfill(60, 84, 200, 72, 1)
    rect(60, 84, 200, 72, 6)
    centre("PAUSED", 96, 10)
    centre("START: RESUME", 116, 7)
    centre("SELECT: QUIT TO MENU", 132, 6)
  elseif state == "over" then
    rectfill(60, 92, 200, 56, 1)
    rect(60, 92, 200, 56, 6)
    centre(result, 104, 10)
    centre("PRESS A", 126, 7)
  end
end
