-- role_king.lua — the Puppet King's role, as Komali wears it once the King
-- is home (fight.lua reads it when he first carries it). B, wide swings of
-- the sceptre, the third the widest; in the air a spin; X, a summons: two
-- shadow soldiers step out beside him and fight for him for 8 seconds,
-- each going for the nearest shadow; every shadow torn, by anyone, makes
-- the next summons come sooner; coming in, a sweep of the cape all round,
-- and while it is up blows from the front are turned aside and the
-- shadows in front thrown back. His frames are on the King's sheet.

local shadows = require("shadows")
local fight   = require("fight")
local move    = require("move")
local fx      = require("fx")
local C       = require("colours")

local SUMMON = { frames = 480, speed = 0.9, sight = 160, reach = 18, wind = 12, n = 8, rest = 24, sooner = 90 }
local CAPE = { frames = 40, n = 4 }
-- the two soldiers summoned: a few long arrays (feet, facing, frames left,
-- what each is doing and for how long, walking step)
local ax, ay, af, at, ast, att, astep = {}, {}, {}, {}, {}, {}, {}
for n = 1, 2 do ax[n], ay[n], af[n], at[n], ast[n], att[n], astep[n] = 0, 0, 1, 0, "walk", 0, 0 end
local cape, cape_swing = 0, 0
local seen_n, seen_on = -1, 0                    -- the shadows in the room, and those standing

local king = {
  name = "King",
  colours = { C.red, C.navy, C.vermil, C.blue, C.red + 32, C.navy + 32,         -- dark robes,
              C.oxblood, C.ink, C.saffron, C.marigold, C.saffron + 32, C.marigold + 32 },   -- worked in gold
  frames = 0,                                      -- his own frames,
  moves = 482, sheet = "king.kolam",               -- and the King's (body.FRAME 14-19), on his sheet
  poses = { "sceptre1", "sceptre2", "sceptre3", air = "k_air", swap = "cape", skill = "summon" },
  combo = { { s = 4, a = 5, r = 9, n = 9, w = 24, h = 18 },
            { s = 4, a = 5, r = 9, n = 9, w = 24, h = 18 },
            { s = 6, a = 6, r = 12, n = 15, w = 30, h = 24, heavy = true } },
  air = { s = 2, a = 8, r = 4, n = 8, w = 16, h = 22, around = true },
  swap = { s = 2, a = 8, r = 8, n = 10, w = 26, h = 22, around = true, heavy = true },
  skill = "summon", wait = 900,
  slow = 0.5, dodge_wait = 1, guard = 0,
  SUMMON = SUMMON, CAPE = CAPE,
}

-- the floor under (x, y), a little way down, or y itself
local function floor_at(x, y)
  for d = 0, 64, 2 do if move.blocked(x, y + d, 1, 1) then return y + d end end
  return y
end

function king.start_skill(k)
  local y = floor_at(k.x + k.w / 2, k.y + k.h)
  for n = 1, 2 do
    ax[n], ay[n], af[n], at[n], ast[n], att[n] = k.x + k.w / 2 + (n == 1 and -16 or 16), y, k.face, SUMMON.frames, "walk", 0
    fx.tear(ax[n], y - 10, 0)
  end
  return 20
end

function king.on_swap(k)
  cape, cape_swing = CAPE.frames, fight.swing
end

-- the nearest shadow standing on a soldier's level, and how far across
local function nearest(n)
  local best, bd = nil, SUMMON.sight
  for _, s in ipairs(shadows.list) do
    if s.on and not s.prop and math.abs(s.y + s.h - ay[n]) < 24 then
      local d = s.x + s.w / 2 - ax[n]
      if math.abs(d) < math.abs(bd) then best, bd = s, d end
    end
  end
  return best, bd
end

local function walk(n, dir)
  af[n] = dir
  local ahead = ax[n] + dir * 6
  if move.blocked(ahead, ay[n], 1, 1) and not move.blocked(ahead, ay[n] - 16, 1, 8) then
    ax[n] = ax[n] + dir * SUMMON.speed
    astep[n] = astep[n] + SUMMON.speed
  end
end

function king.each(k)
  -- every shadow torn makes the next summons come sooner (the room's
  -- shadows are made when it is entered: a new count is a new room)
  local on = 0
  for _, s in ipairs(shadows.list) do if s.on and not s.prop then on = on + 1 end end
  if #shadows.list == seen_n and on < seen_on then fight.shorten((seen_on - on) * SUMMON.sooner) end
  seen_n, seen_on = #shadows.list, on
  -- the cape: blows from the front turned aside; the shadows in front thrown back
  if cape > 0 then
    cape = cape - 1
    if fight.role() == king then
      k.guard = -1
      for _, s in ipairs(shadows.list) do
        if s.on and not s.prop and s.hit ~= cape_swing and shadows.overlap(k.face > 0 and k.x + k.w or k.x - 16, k.y, 16, k.h, s) then
          s.hit = cape_swing
          if shadows.strike(s, CAPE.n, k.face, true) then fight.hit(false) end
        end
      end
    end
  end
  -- the soldiers summoned
  for n = 1, 2 do
    if at[n] > 0 then
      at[n] = at[n] - 1
      local s, d = nearest(n)
      if ast[n] == "walk" then
        if s and math.abs(d) > SUMMON.reach then walk(n, d < 0 and -1 or 1)
        elseif s then af[n], ast[n], att[n] = d < 0 and -1 or 1, "wind", SUMMON.wind
        elseif math.abs(k.x + k.w / 2 - ax[n]) > 28 then walk(n, k.x + k.w / 2 < ax[n] and -1 or 1) end
      else
        att[n] = att[n] - 1
        if att[n] <= 0 and ast[n] == "wind" then                -- the blow
          for _, o in ipairs(shadows.list) do
            if o.on and not o.prop and shadows.overlap(af[n] > 0 and ax[n] or ax[n] - 18, ay[n] - 18, 18, 12, o) then
              local r = shadows.strike(o, fight.cost(SUMMON.n, king), af[n], false)
              if r == "hit" or r == "torn" then fight.hit(false) end
            end
          end
          ast[n], att[n] = "strike", SUMMON.rest
        elseif att[n] <= 0 then ast[n] = "walk" end
      end
      if at[n] == 0 then fx.tear(ax[n], ay[n] - 10, 0) end
    end
  end
end

-- the soldiers, dark, from the actors' sheet (shadows.lua's frames); the
-- cape, a ring while it is up
function king.draw_each(k)
  if cape > 0 and fight.role() == king then
    circ(k.x + k.w / 2, k.y + k.h / 2, 14, stat("frame") % 4 < 2 and C.red or C.marigold)
  end
  local up = false
  for n = 1, 2 do
    if at[n] > 0 and (at[n] > 60 or stat("frame") % 4 < 2) then
      if not up then shadows.dark() up = true end
      local f = ast[n] == "wind" and 527 or ast[n] == "strike" and 530 or 515 + astep[n] // 6 % 4 * 3
      spr(f, math.floor(ax[n]) - 12, math.floor(ay[n]) - 32, 3, 4, af[n] < 0)
    end
  end
  if up then pal() end
end

-- (for the tests) how many soldiers stand summoned
function king.summoned() return (at[1] > 0 and 1 or 0) + (at[2] > 0 and 1 or 0) end

return king
