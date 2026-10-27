-- title.lua — the title: the shadow theatre at night (bg_title.kolam), the
-- game's name on a banner, and three save slots, each a card showing how
-- many runs it has played through, its oil, and the puppets it has saved.
-- main.lua reads it at the start, and from the pause, and lets it go once
-- a slot is chosen.
--
--   title.open()                the title, over everything
--   title.update(input, select) once a frame: the slot chosen, or nil
--   title.draw()
--   title.skip                  a slot to choose at once, with no title
--                               (the tests set it)
--
-- Left and right choose a slot; A plays it (a new one starts empty); X
-- twice empties it; SELECT changes the language, for every slot.

local run   = require("run")
local rooms = require("rooms")
local lines = require("lines")
local text  = require("text")
local I     = require("icons")
local C     = require("colours")

local title = { skip = nil }

-- what a slot holds: runs played through, oil, the puppets saved, a run
-- kept at a door, the King come home, his shadow torn; nil if it is empty
local function peek(slot)
  local d = run.read(slot)
  if not d then return nil end
  return { played = d.played or 0, oil = d.oil or 0, saved = d.saved or {}, kept = d.kept and true or false,
           king = d.king, ending_b = d.ending_b }
end
title.peek = peek

local function empty(slot)
  save(run.SLOT .. slot, nil)
  if slot == 1 then save(run.OLD, nil) end
  save_commit()
end
local PUPPETS = { "veeran", "vil", "aattakkaari", "yaanai", "mandhiri", "rani" }
local at, erase, peeks = 1, 0, {}

function title.open()
  rooms.dress("title", "bg_title.kolam")
  rooms.music(rooms.TITLE)
  lines.use(run.language())
  for n = 1, 3 do peeks[n] = peek(n) end
  erase = 0
end

function title.update(i, select_p)
  if select_p then run.set_language(lines.lang == "ta" and "en" or "ta") end
  if i.left_p then at, erase = (at + 1) % 3 + 1, 0 end
  if i.right_p then at, erase = at % 3 + 1, 0 end
  if i.skill and peeks[at] then                    -- X, and X again: the slot emptied
    erase = erase + 1
    if erase >= 2 then empty(at) peeks[at], erase = nil, 0 end
  end
  if i.jump then return at end
  return nil
end

local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

local function card(n, x, y)
  local p, lit = peeks[n], n == at
  rectfill(x, y, 92, 56, lit and C.wood or C.deep)
  rect(x, y, 92, 56, lit and C.lamp or C.leather)
  if lit then rect(x - 1, y - 1, 94, 58, C.marigold) end
  font()
  text.outline(tostring(n), x + 6, y + 4, lit and C.lamp or C.tan, C.ink)
  font("small")
  if not p then
    local s = lines.t("new_slot")
    print(s, x + 46 - text.width(s) // 2, y + 22, lit and C.cloth or C.tan)
    return
  end
  spr(I.done, x + 24, y + 3, 2, 2)                 -- runs played through
  print(p.played, x + 44, y + 6, C.cloth)
  spr(791, x + 28, y + 23)                         -- oil
  print(p.oil, x + 44, y + 21, C.lamp)
  for k, r in ipairs(PUPPETS) do                   -- a bead for each puppet saved
    circfill(x + 12 + (k - 1) * 14, y + 45, 3, has(p.saved, r) and C.marigold or C.ink)
    circ(x + 12 + (k - 1) * 14, y + 45, 3, C.leather)
  end
  if p.king then circfill(x + 84, y + 8, 2, C.glow) end      -- the King come home
  if p.ending_b then circfill(x + 76, y + 8, 2, C.sky) end   -- and his shadow torn
  if p.kept then                                   -- a run waiting at a door: a flame
    pset(x + 84, y + 20, C.glow) line(x + 83, y + 21, x + 85, y + 21, C.lamp) pset(x + 84, y + 22, C.saffron)
  end
end

function title.draw()
  cls()                                            -- the theatre (the backdrop)
  -- the banner across the booth's roof
  rectfill(70, 1, 180, 38, C.oxblood)
  rect(70, 1, 180, 38, C.marigold)
  rect(72, 3, 176, 34, C.red)
  font()
  text.outline("நிழலாட்டம்", 160 - text.width("நிழலாட்டம்") // 2, 5, C.lamp, C.ink)
  font("small")
  text.outline("NIZHALATTAM", 160 - text.width("NIZHALATTAM") // 2, 26, C.cloth, C.ink)
  sheet.load(rooms.ACTORS)                         -- (the icons are on the actors' sheet)
  for n = 1, 3 do card(n, 8 + (n - 1) * 104, 178) end
  local s = erase == 1 and lines.t("erase_q", buttons.x)
            or lines.t("title_keys", buttons.a, buttons.x, buttons.select)
  text.outline(s, 160 - text.width(s) // 2, 164, erase == 1 and C.vermil or C.glow, C.ink)
  font()
end

return title
