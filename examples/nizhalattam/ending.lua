-- ending.lua — the endings, as scenes: a few panels each, played on the
-- theatre's lit cloth in front of the Courtyard at night, with a line under
-- each. main.lua reads it when an ending begins, and lets it go after.
--
--   ending.open("a" or "b")   Ending A (the King home) or B (his shadow torn)
--   ending.update(input)      once a frame: true when the last panel is done
--   ending.draw()
--
-- A panel stays a while (A goes on sooner, after a moment); between panels
-- the picture darkens and comes back. main.lua leaves the palace for the
-- Courtyard first, so its code is let go while the scene plays.

local lines = require("lines")
local text  = require("text")
local fx    = require("fx")
local C     = require("colours")

local scene = {}

-- the scenes' words, in each language (here, not in the palace's: the
-- palace is let go before a scene plays)
local WORDS = {
  en = {
    ending_b = "The King's shadow tears: the last of the anger he was painted with",
    end_a1 = "The Puppet Master scrapes at the King's paint, and finds old colours under it: a hero's",
    end_a2 = "On the festival's last night the troupe plays, and for one night the King is the hero",
    end_a3 = "The Jester falls over for a laugh, as always. It is the biggest laugh of the season",
    end_b2 = "The Puppet Master carves the Jester a role of his own",
    end_b3 = "A new play, the first in fifty years: the King and the clown in it together",
  },
  ta = {
    ending_b = "அரசனின் நிழல் கிழிகிறது: அவன் மேல் தீட்டப்பட்ட கோபத்தின் கடைசித் துளி",
    end_a1 = "ஆசான் அரசனின் வண்ணத்தைச் சுரண்டுகிறார்; அதன் அடியில் பழைய வண்ணங்கள்: ஒரு நாயகனுடையவை",
    end_a2 = "திருவிழாவின் கடைசி இரவில் குழு ஆடுகிறது; ஒரு இரவுக்கு அரசனே நாயகன்",
    end_a3 = "கோமாளி எப்போதும் போல் சிரிப்புக்காக விழுகிறான். இந்தப் பருவத்தின் மிகப் பெரிய சிரிப்பு அது",
    end_b2 = "ஆசான் கோமாளிக்கென்றே ஒரு வேடம் செதுக்குகிறார்",
    end_b3 = "ஐம்பது ஆண்டுகளில் முதல் புதிய நாடகம்: அதில் அரசனும் கோமாளியும் சேர்ந்து",
  },
}

local HOLD, SOON, FADE = 360, 40, 16         -- frames a panel stays, before A moves it on, fading
local SHEETS = { "king.kolam", "vil.kolam", "aatta.kolam", "yaanai.kolam", "mandhiri.kolam", "rani.kolam" }

-- the puppets of the troupe, as they stand in a play: their sheet, frame,
-- size in cells (the Warrior is on the actors' sheet)
local TROUPE = {
  { "actors.kolam", 1024, 6 }, { "vil.kolam", 0, 6 }, { "aatta.kolam", 0, 6 },
  { "yaanai.kolam", 0, 8 }, { "mandhiri.kolam", 0, 6 }, { "rani.kolam", 0, 6 },
}

-- the panels: what is drawn (by name, below), and the line under it
local PANELS = {
  a = { { "paint", "end_a1" }, { "hero", "end_a2" }, { "laugh", "end_a3" } },
  b = { { "torn", "ending_b" }, { "carve", "end_b2" }, { "play", "end_b3" } },
}

local list, at, t, said = nil, 1, 0, nil
local NOBODY = { x = -999, y = -999, w = 0, h = 0 }

local function caption(key)
  font("small")
  said = table.concat(text.wrap(WORDS[lines.lang][key], 40), "\n")
  font()
end

function scene.open(which)
  for _, s in ipairs(SHEETS) do preload(s) end
  list, at, t = PANELS[which], 1, 0
  caption(list[1][2])
  fx.clear()
  local rooms = require("rooms")
  rooms.music(rooms.ENDING)
end

function scene.update(i)
  t = t + 1
  if t > SOON and t < HOLD - FADE and i.jump then t = HOLD - FADE end      -- A: on to the fade
  if t >= HOLD then
    at, t = at + 1, 0
    if at > #list then return true end
    caption(list[at][2])
  end
  fx.update(NOBODY)                                      -- (the scraps fly; nothing picks up ink)
  return false
end

-- the cloth: lit from behind, brightest at its middle, in a carved frame;
-- the lamps along its foot
local FEET = 168                             -- where the puppets stand on it
local function cloth()
  rectfill(34, 8, 252, 172, C.wood)
  rect(34, 8, 252, 172, C.marigold)
  rectfill(40, 14, 240, 160, C.warm)
  rectfill(56, 22, 208, 146, C.cloth)
  circfill(160, 110, 62, C.glow)
  for x = 44, 276, 24 do circfill(x, 178, 2, C.lamp) pset(x, 175, C.glow) end
end

local function puppet(sheet_, n, w, cx, flip)
  sheet.load(sheet_)
  spr(n, cx - w * 4, FEET - 63, w, 8, flip)
end

-- a sprite from the actors' sheet, twice the size (the Courtyard is seen close)
local function big(n, w, h, x, y)
  sheet.load("actors.kolam")
  sspr(n % 64 * 8, n // 64 * 8, w * 8, h * 8, x, y, w * 16, h * 16)
end

local function ground()
  rectfill(0, 150, 320, 36, C.ink)
  line(0, 150, 319, 150, C.deep)
end

local DRAW = {}
function DRAW.paint(f)                       -- at his box, the Puppet Master scraping at the King's face
  ground()
  big(771, 3, 2, 170, 152)
  big(512 + (8 + f // 30 % 2) * 3, 3, 4, 110, 120)
  big(1934, 2, 2, 150, 136)                             -- the King's face, in his hands
  if f % 20 < 10 then pset(160, 150, C.glow) end
  if f > 120 then                                       -- the old colours, showing through
    for d = 0, 5 do pset(154 + d * 4, 140 + (f // 6 + d) % 20, d % 2 == 0 and C.sky or C.marigold) end
  end
end
function DRAW.hero(f)                        -- the King, the hero for one night; the troupe about him
  cloth()
  for n, p in ipairs(TROUPE) do
    puppet(p[1], p[2], p[3], n <= 3 and 50 + n * 24 or 170 + (n - 3) * 28, n <= 3)
  end
  puppet("king.kolam", f // 40 % 2 == 0 and 0 or 30, 6, 160, false)
end
function DRAW.laugh(f)                       -- the Jester falls over; the audience laughs
  cloth()
  puppet("king.kolam", 0, 6, 200, true)
  local fallen = f % 120 > 50
  sheet.load("actors.kolam")
  spr(fallen and 54 or 6 + f // 6 % 6 * 3, 96 + (fallen and 25 or (f % 120) // 2), FEET - 32, 3, 4)
  if fallen then
    for d = 0, 6 do                                       -- laughter rising from the dark
      print("ha", 50 + d * 34 + (f // 8 + d) % 3, 182 - (f % 40) // 4 - d % 2 * 3, d % 2 == 0 and C.lamp or C.marigold)
    end
  end
end
function DRAW.torn(f)                        -- the King's shadow, tearing
  cloth()
  if f < 240 then
    require("shadows").dark()
    puppet("king.kolam", f // 8 % 2 == 0 and 518 or 0, 6, 160, false)
    pal()
    if f % 8 == 0 then fx.tear(146 + f % 30, 120 + f % 36, 0) end
  end
end
function DRAW.carve(f)                       -- the Puppet Master carving the Jester a role
  ground()
  big(771, 3, 2, 150, 152)
  big(512 + (8 + f // 20 % 2) * 3, 3, 4, 90, 120)
  big(f // 40 % 2 == 0 and 0 or 3, 3, 4, 210, 120)
  if f % 16 < 8 then pset(140, 160, C.glow) pset(141, 159, C.lamp) end      -- the knife's glint
end
function DRAW.play(f)                        -- the new play: the King and the clown together
  cloth()
  for n, p in ipairs(TROUPE) do
    puppet(p[1], p[2], p[3], n <= 3 and 40 + n * 22 or 196 + (n - 3) * 24, n <= 3)
  end
  puppet("king.kolam", f // 50 % 2 == 0 and 0 or 30, 6, 140, false)
  sheet.load("actors.kolam")
  spr(f // 90 % 2 == 0 and f // 30 % 2 or 54, 168, FEET - 32, 3, 4, true)
end

function scene.draw()
  local f = t
  local edge = math.min(f, HOLD - f)                    -- near a panel's start or end: dark
  if edge < FADE // 2 then cls(C.ink) return end
  cls()
  if edge < FADE then for c = 0, 31 do pal(c, c + 32) end end
  DRAW[list[at][1]](f)
  sheet.load("actors.kolam")
  fx.draw()
  -- the line, in a dark band along the foot
  rectfill(0, 186, 320, 54, C.ink)
  line(0, 186, 319, 186, C.marigold)
  font("small")
  local h, n = text.height(said:match("[^\n]+")) + 2, select(2, said:gsub("\n", "")) + 1
  local y = 213 - h * n // 2
  for l in said:gmatch("[^\n]+") do
    text.outline(l, 160 - text.width(l) // 2, y, C.glow, C.ink)
    y = y + h
  end
  font()
  pal()
end

return scene
