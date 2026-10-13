-- pong — first to seven: against the console, against a second player on
-- the same console, or against another console over the link.
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
local players                       -- 1: against the console, 2: two people on
                                    -- one console, 3: two linked consoles
local modes                         -- how many of those this console offers
local left, right, ball
local level                         -- index into LEVELS, kept between runs
local ai_aim, timer, shake, wins, wins_text, level_text, result

-- Link play. The console the link calls side 1 runs the match and plays the
-- left paddle; side 2 plays the right paddle and draws what it is told.
-- Every frame side 2 sends its paddle and side 1 sends the whole court:
--   side 2 -> 1   "G", paddle y, flags (1: toggle pause, 2: give up)
--   side 1 -> 2   "H", state, ball x, ball y, left paddle y, both scores,
--                 flags (1: paused, 2: shaking), winner (0, 1 or 2)
local GUEST_FMT, HOST_FMT = "<BhB", "<BBhhhBBBB"
local GUEST_TAG, HOST_TAG = 71, 72
local GUEST_LEN, HOST_LEN = string.packsize(GUEST_FMT), string.packsize(HOST_FMT)
local STATE_CODE = { menu = 0, serve = 1, play = 2, over = 3 }
local STATE_NAME = { [0] = "menu", "serve", "play", "over" }
local PEER_TIMEOUT = 30             -- frames of silence before the peer counts as away

local linked                        -- link play chosen and the other console answering
local peer_quiet                    -- frames since the other console last spoke
local peer_y                        -- side 2's paddle, as side 1 last heard it
local peer_pause, peer_quit         -- what side 2 asked for this frame
local link_lost                     -- the last link match ended because the link dropped

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
  modes = sys.has("link") and 3 or 2
  linked, peer_quiet, peer_y = false, PEER_TIMEOUT, H / 2 - PAD_H / 2
  peer_pause, peer_quit, link_lost = false, false, false
  wins = {}
  for i = 1, #LEVELS do wins[i] = load("wins" .. i, 0) end
  set_level(load("level", 2))
  result = ""
  paused = false
  a_was_down = false
  state = "menu"
end

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
  elseif players == 2 then          -- the second player shares this console
    if btn("x") then right.y = right.y - PAD_SPEED * dt end
    if btn("b") then right.y = right.y + PAD_SPEED * dt end
    right.y = clamp(right.y, 0, H - PAD_H)
  else                              -- the second player is on the other console
    right.y = clamp(peer_y, 0, H - PAD_H)
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
  elseif players == 3 then
    result = winner == left and "YOU WIN" or "YOU LOSE"
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
  if ball.y < R then ball.y = R; ball.vy = -ball.vy; sfx(3) end
  if ball.y > H - R then ball.y = H - R; ball.vy = -ball.vy; sfx(3) end

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

-- Side 1: hear what side 2 sent.
local function host_listen()
  peer_pause, peer_quit = false, false
  peer_quiet = peer_quiet + 1
  while true do
    local m = link.recv()
    if not m then break end
    if #m == GUEST_LEN and m:byte(1) == GUEST_TAG then
      local _, y, flags = string.unpack(GUEST_FMT, m)
      peer_y, peer_quiet = y, 0
      if flags & 1 ~= 0 then peer_pause = true end
      if flags & 2 ~= 0 then peer_quit = true end
    end
  end
end

-- Side 1: tell side 2 what the court looks like now.
local function host_tell()
  local flags = (paused and 1 or 0) | (shake > 0 and 2 or 0)
  local winner = 0
  if state == "over" then winner = left.score > right.score and 1 or 2 end
  link.send(string.pack(HOST_FMT, HOST_TAG, STATE_CODE[state],
                        math.floor(ball.x), math.floor(ball.y), math.floor(left.y),
                        left.score, right.score, flags, winner))
end

-- Side 2: take the court from side 1, move our own paddle, report it.
local function guest_frame(dt)
  peer_quiet = peer_quiet + 1
  while true do
    local m = link.recv()
    if not m then break end
    if #m == HOST_LEN and m:byte(1) == HOST_TAG then
      local _, code, bx, by, ly, ls, rs, flags, winner = string.unpack(HOST_FMT, m)
      local was = state
      state = STATE_NAME[code] or "menu"
      if was == "menu" and state ~= "menu" then right.y = H / 2 - PAD_H / 2 end
      ball.x, ball.y, left.y = bx, by, ly
      -- Side 1 sends the court, not its sounds: work them out from what changed.
      if ls ~= left.score or rs ~= right.score then sfx(2) end
      if flags & 2 ~= 0 and shake <= 0 then sfx(0) end
      if ls ~= left.score then set_score(left, ls) end
      if rs ~= right.score then set_score(right, rs) end
      paused = flags & 1 ~= 0
      shake = flags & 2 ~= 0 and 0.05 or 0
      if winner ~= 0 then result = winner == 2 and "YOU WIN" or "YOU LOSE" end
      peer_quiet = 0
    end
  end

  local flags = 0
  if state == "serve" or state == "play" then
    if btnp("start") then flags = 1 end
    if paused then
      if btnp("select") then flags = flags | 2 end
    else
      if btn("up")   then right.y = right.y - PAD_SPEED * dt end
      if btn("down") then right.y = right.y + PAD_SPEED * dt end
      right.y = clamp(right.y, 0, H - PAD_H)
    end
  end
  link.send(string.pack(GUEST_FMT, GUEST_TAG, math.floor(right.y), flags))
end

-- One frame of the game for whoever runs the match: a console on its own,
-- or side 1 of a link.
local function play_frame(dt, confirm)
  -- START pauses a match and resumes it; while paused, SELECT gives up.
  -- Over the link, either player may do both.
  if state == "serve" or state == "play" then
    if btnp("start") or peer_pause then paused = not paused end
    if paused then
      if btnp("select") or peer_quit then paused = false; state = "menu" end
      return
    end
  end

  if shake > 0 then shake = shake - dt end

  if state == "menu" then
    if btnp("up")   then players = (players - 2) % modes + 1 end
    if btnp("down") then players = players % modes + 1 end
    if players == 1 then
      if btnp("left")  then set_level(level - 1) end
      if btnp("right") then set_level(level + 1) end
    end
    -- A link match needs the other console to have chosen link play too.
    if confirm and (players ~= 3 or (linked and peer_quiet < PEER_TIMEOUT)) then
      -- The runtime starts every game with the same random sequence. How
      -- long the player took to press the button makes each match differ.
      math.randomseed(stat("frame"))
      save("level", level)
      link_lost = false
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

function update(dt)
  -- btnp("a") repeats while A is held, which suits scrolling but not
  -- confirming: one long press must not start a match and then skip the
  -- result. So A counts here only when it has been let go in between.
  local a_down = btn("a")
  local confirm = (a_down and not a_was_down) or btnp("start")
  a_was_down = a_down

  linked = players == 3 and link.status() == "connected"
  if players == 3 and not linked and state ~= "menu" then
    state, paused, link_lost = "menu", false, true      -- the cable came out
  end
  peer_pause, peer_quit = false, false

  if linked and link.side() == 2 then
    -- Leaving link play is the only thing side 2 decides for itself.
    if state == "menu" and (btnp("up") or btnp("down")) then
      players = btnp("up") and 2 or 1
      return
    end
    guest_frame(dt)
  else
    if linked then host_listen() end
    play_frame(dt, confirm)
    if linked then host_tell() end
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
    rectfill(40, 40, 240, 180, 1)
    rect(40, 40, 240, 180, 6)
    centre("P O N G", 50, 7)
    centre(TARGET_TEXT, 64, 6)
    centre(players == 1 and "> 1 PLAYER <" or "1 PLAYER", 84, players == 1 and 10 or 13)
    centre(players == 2 and "> 2 PLAYERS <" or "2 PLAYERS", 98, players == 2 and 10 or 13)
    if modes == 3 then
      centre(players == 3 and "> LINK PLAY <" or "LINK PLAY", 112, players == 3 and 10 or 13)
    end
    if players == 1 then
      centre(level_text, 134, 9)
      centre("LEFT/RIGHT CHANGE THE LEVEL", 148, 6)
      centre("PRESS A TO START", 166, 7)
      centre(wins_text, 182, 13)
    elseif players == 2 then
      centre("P1: UP/DOWN   P2: X/B", 141, 6)
      centre("PRESS A TO START", 166, 7)
    elseif not linked then
      centre(link_lost and "THE LINK WAS LOST" or "LINK THE TWO CONSOLES", 134, 9)
      centre("WAITING FOR THE OTHER ONE", 148, 6)
    elseif link.side() == 2 then
      centre("YOU ARE PLAYER 2 (RIGHT)", 134, 9)
      centre("PLAYER 1 STARTS THE MATCH", 148, 6)
    elseif peer_quiet < PEER_TIMEOUT then
      centre("YOU ARE PLAYER 1 (LEFT)", 134, 9)
      centre("PLAYER 2 IS READY", 148, 6)
      centre("PRESS A TO START", 166, 7)
    else
      centre("YOU ARE PLAYER 1 (LEFT)", 134, 9)
      centre("PLAYER 2: CHOOSE LINK PLAY", 148, 6)
    end
    centre("START PAUSES A MATCH", 204, 5)
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
    centre(linked and link.side() == 2 and "PLAYER 1 CONTINUES" or "PRESS A", 126, 7)
  end
end
