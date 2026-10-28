-- talk.lua — the box people talk in: a speaker's name and their words,
-- typed out a word at a time.
--
--   local talk = require("talk")
--   talk.say("Paati", "Light the lamps, child.", function() ... end)
--   if talk.update(dt) then return end    -- the game waits while people talk
--   talk.draw()                           -- last, with camera() reset
--
-- A shows the rest of a box at once, then moves on. Long words are wrapped
-- and split over as many boxes as they need. This is a lighter cousin of the
-- SDK's dialog helper: it shows words whole, so it never has to know where a
-- Tamil letter ends, and it keeps nothing it does not need, as the game is
-- short of Lua memory.

local core     = require("core")
local progress = require("progress")

local talk = {}
local X, W, PAD = 8, 304, 6
local queue, first = {}, 1         -- what is waiting to be said
local who, lines, page, rows       -- the box on screen
local words, wx, wy, nwords = {}, {}, {}, 0    -- the words of this page and where each goes
local shown, clock, box_h, was_down

function talk.say(name, line, done)
  queue[#queue + 1] = { name, line, done }
end

function talk.active()
  return who ~= nil or first <= #queue
end

function talk.clear()
  for i = #queue, 1, -1 do queue[i] = nil end
  first, who = 1, nil
end

-- Lay out one page: its lines split into words, each with its place.
local function open_page()
  nwords = 0
  local line_h = core.height(lines[page]) + 2
  local y = 0
  for r = page, math.min(page + rows - 1, #lines) do
    local x = 0
    for word in lines[r]:gmatch("%S+") do
      nwords = nwords + 1
      words[nwords], wx[nwords], wy[nwords] = word, x, y
      x = x + core.width(word .. " ")
    end
    y = y + line_h
  end
  for i = nwords + 1, #words do words[i] = nil end
  box_h = y + 18
  shown, clock = 0, 0
end

local function next_entry()
  local e = queue[first]
  if not e then
    for i = #queue, 1, -1 do queue[i] = nil end
    first, who = 1, nil
    return
  end
  first = first + 1
  who, lines, page = e[1], core.wrap(e[2], (W - 2 * PAD) // 8), 1
  rows = core.height(lines[1]) > 8 and 3 or 5          -- Tamil lines are taller
  talk.done = e[3]
  open_page()
end

-- True while there is anything to show, and on the frame the last box
-- closes, so the press of A that closed it is not taken for another.
function talk.update(dt)
  if not who then
    if first > #queue then return false end
    next_entry()
    was_down = true                   -- the press that began the talking is not one for it
  end
  local down = btn("a")
  local pressed = down and not was_down
  was_down = down
  if shown < nwords then
    clock = clock + dt
    local due = math.floor(clock * 12)
    if due > shown then
      shown = math.min(nwords, due)
      if shown % 2 == 1 then progress.sfx(16, 7) end   -- blip
    end
    if pressed then shown = nwords end
    return true
  end
  if pressed then
    if page + rows <= #lines then
      page = page + rows
      open_page()
    else
      local done = talk.done
      talk.done = nil
      next_entry()
      if done then done() end
    end
  end
  return true
end

function talk.draw()
  if not who then return end
  local y = 236 - box_h
  rectfill(X, y, W, box_h, 32)
  rect(X, y, W, box_h, 10)
  if who ~= "" then
    local w = core.width(who) + 8
    rectfill(X + 6, y - 6 - core.height(who) // 2, w, core.height(who) + 2, 32)
    print(who, X + 10, y - 5 - core.height(who) // 2, 10)
  end
  for i = 1, shown do
    print(words[i], X + PAD + wx[i], y + 10 + wy[i], 7)
  end
  if shown >= nwords and stat("frame") // 20 % 2 == 0 then
    print(">", X + W - 12, y + box_h - 10, 10)
  end
end

return talk
