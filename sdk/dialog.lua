-- dialog.lua — a box of text for people to talk in.
--
--   local dialog = require("dialog")
--
--   dialog.say("Elder", "Welcome, traveller. The road north is closed.")
--   dialog.ask("Elder", "Will you help us?", { "Yes", "Not now" },
--     function(choice)                  -- 1 for "Yes", 2 for "Not now"
--       if choice == 1 then dialog.say("Elder", "Thank you!") end
--     end)
--
--   function update(dt)
--     if dialog.update(dt) then return end   -- the game waits while people talk
--     -- ... the rest of your game
--   end
--
--   function draw()
--     -- ... your game, then, after camera():
--     dialog.draw()
--   end
--
-- Text appears a letter at a time. A shows the rest at once, then moves on;
-- up and down choose an answer and A picks it. Long text is wrapped and
-- split over as many boxes as it needs. A new line can be forced with \n.
--
-- dialog.say(who, text, done)   Queue something to be said. `who` is the
--     speaker's name, or nil for none. `done`, if given, is called when the
--     player has read it.
-- dialog.ask(who, text, options, done)   Queue a question. `options` is a
--     list of answers; done(index, answer) is called with the one chosen.
-- dialog.update(dt)   Call once a frame. True while there is anything to show,
--     and on the frame the last box is closed: that press of A belongs to
--     the talking, so a game that starts talking on A does not start again.
-- dialog.draw()       Call at the end of draw(), with the camera reset.
-- dialog.active()     True while there is anything to show.
-- dialog.clear()      Drop everything queued.
--
-- To change how it looks, set these before use:
--     dialog.x, dialog.y, dialog.w   the box's corner and width (8, 176, 304)
--     dialog.rows     lines of text in the box (3)
--     dialog.speed    letters a second; 0 shows text at once (45)
--     dialog.blip     a sound number to play as letters appear (none)
--     dialog.colors   back, border, text, name, choice
--
-- This file is part of the Pulli SDK. Copy it into your game and change it
-- as you like.

local dialog = {
  x = 8, y = 176, w = 304,
  rows = 3,
  speed = 45,
  blip = nil,
  colors = { back = 32, border = 7, text = 7, name = 10, choice = 10 },
}

local LETTER, LINE, PAD = 8, 10, 8     -- a letter is 8 pixels wide; lines are 10 apart

local queue = {}                -- what is waiting to be said; queue[1] is on screen
local page, shown = 1, 0        -- which box of queue[1], and how many letters of it show
local letters = 0               -- how many letters the box holds
local choice = 1
local a_was, up_was, down_was = true, true, true
local partial, partial_for = "", -1    -- the half-shown line, rebuilt only when it changes
local blip_wait = 0

-- Break text into lines that fit `columns` letters, at spaces where possible.
local function wrap(text, columns)
  local lines = {}
  for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
    local line = ""
    for word in string.gmatch(paragraph, "%S+") do
      while #word > columns do            -- a word too long for a line: cut it
        if line ~= "" then lines[#lines + 1] = line; line = "" end
        lines[#lines + 1] = string.sub(word, 1, columns)
        word = string.sub(word, columns + 1)
      end
      if line == "" then
        line = word
      elseif #line + 1 + #word <= columns then
        line = line .. " " .. word
      else
        lines[#lines + 1] = line
        line = word
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

local function count_letters(entry, on_page)
  local n = 0
  for i = (on_page - 1) * dialog.rows + 1, math.min(on_page * dialog.rows, #entry.lines) do
    n = n + #entry.lines[i]
  end
  return n
end

-- Put a box of queue[1] on screen, from its first letter.
local function open(on_page)
  page, choice, partial_for = on_page, 1, -1
  letters = count_letters(queue[1], page)
  shown = dialog.speed > 0 and 0 or letters
  a_was, up_was, down_was = true, true, true    -- a button already down does not count
end

local function add(who, text, options, done)
  local columns = (dialog.w - 2 * PAD) // LETTER
  local entry = { who = who, lines = wrap(tostring(text), columns), options = options, done = done }
  entry.pages = math.max(1, (#entry.lines + dialog.rows - 1) // dialog.rows)
  queue[#queue + 1] = entry
  if #queue == 1 then open(1) end
end

function dialog.say(who, text, done)
  add(who, text, nil, done)
end

function dialog.ask(who, text, options, done)
  if type(options) ~= "table" or #options == 0 then error("dialog.ask: give a list of answers", 2) end
  add(who, text, options, done)
end

function dialog.active()
  return #queue > 0
end

function dialog.clear()
  for i = #queue, 1, -1 do queue[i] = nil end
end

-- True on the frame a button goes down. btnp() would also fire again while
-- the button is held, which would skip through the text.
local function pressed(name, was)
  local down = btn(name)
  return down and not was, down
end

function dialog.update(dt)
  local entry = queue[1]
  if not entry then return false end

  local a, up, down
  a, a_was = pressed("a", a_was)
  up, up_was = pressed("up", up_was)
  down, down_was = pressed("down", down_was)

  if shown < letters then                       -- still appearing
    if a then
      shown = letters
    else
      local before = math.floor(shown)
      shown = math.min(letters, shown + dialog.speed * dt)
      blip_wait = blip_wait - dt
      if dialog.blip and math.floor(shown) > before and blip_wait <= 0 then
        sfx(dialog.blip)
        blip_wait = 0.06
      end
    end
    return true
  end

  local asking = entry.options and page == entry.pages
  if asking then
    if up then choice = (choice - 2) % #entry.options + 1 end
    if down then choice = choice % #entry.options + 1 end
  end
  if a then
    if page < entry.pages then
      open(page + 1)
    else
      local picked = choice
      table.remove(queue, 1)
      if queue[1] then open(1) end
      -- Called last, so that it can queue more to say.
      if entry.done then
        if asking then entry.done(picked, entry.options[picked]) else entry.done() end
      end
    end
  end
  return true                   -- even if that press closed the last box
end

function dialog.draw()
  local entry = queue[1]
  if not entry then return end
  local c = dialog.colors
  local x, y, w = dialog.x, dialog.y, dialog.w
  local h = dialog.rows * LINE + 2 * PAD - 2

  rectfill(x, y, w, h, c.back)
  rect(x, y, w, h, c.border)
  if entry.who then                             -- the speaker's name, on a tab above the box
    local tab = #entry.who * LETTER + 8
    rectfill(x + 6, y - 11, tab, 12, c.back)
    rect(x + 6, y - 11, tab, 12, c.border)
    rectfill(x + 7, y, tab - 2, 1, c.back)      -- join the tab to the box
    print(entry.who, x + 10, y - 8, c.name)
  end

  local left = math.floor(shown)                -- letters still to draw
  local first = (page - 1) * dialog.rows + 1
  for i = first, math.min(page * dialog.rows, #entry.lines) do
    local line = entry.lines[i]
    local ty = y + PAD + (i - first) * LINE
    if left >= #line then
      print(line, x + PAD, ty, c.text)
    elseif left > 0 then
      if partial_for ~= left then               -- make the cut-off line only when it grows
        partial, partial_for = string.sub(line, 1, left), left
      end
      print(partial, x + PAD, ty, c.text)
    end
    left = left - #line
    if left <= 0 then break end
  end
  if shown < letters then return end

  if entry.options and page == entry.pages then -- the answers, in a box of their own
    local longest = 0
    for i = 1, #entry.options do longest = math.max(longest, #entry.options[i]) end
    local bw, bh = (longest + 2) * LETTER + 2 * PAD, #entry.options * LINE + 2 * PAD - 2
    local bx, by = x + w - bw, y - bh - 4
    rectfill(bx, by, bw, bh, c.back)
    rect(bx, by, bw, bh, c.border)
    for i = 1, #entry.options do
      local ty = by + PAD + (i - 1) * LINE
      if i == choice then print(">", bx + PAD, ty, c.choice) end
      print(entry.options[i], bx + PAD + 2 * LETTER, ty, i == choice and c.choice or c.text)
    end
  elseif math.floor(time() * 2) % 2 == 0 then   -- a blinking mark: there is more, press A
    print("v", x + w - 14, y + h - 11, c.border)
  end
end

return dialog
