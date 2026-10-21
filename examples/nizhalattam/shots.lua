-- shots.lua — arrows in flight: Komali's (the archer's role) and the
-- shadows' (Vil's).
--
--   shots.fire(x, y, vx, vy, life, n, mine, heavy)   an arrow from (x, y);
--                             heavy ones pass through what they strike
--   shots.update(body, shadows)   once a frame: returns how many shadows
--                             Komali's arrows struck, and whether a heavy one
--   shots.draw()
--   shots.clear()             at every door
--   shots.streak              Komali's arrows that struck in a row (the
--                             archer's arrows fly further for each)
--
-- An arrow flies straight, stops at a wall, and is gone when its life runs
-- out. Komali's strike shadows as a blow from the side they fly from; the
-- shadows' hurt Komali, pass through him while he cannot be touched, and
-- break on the warrior's shield. Kept in a few long arrays: nothing is made
-- while playing.

local move = require("move")
local fx   = require("fx")
local C    = require("colours")

local shots = { streak = 0 }

local MAX = 24
local MINE, HEAVY, GOT = 1, 2, 4                -- an arrow's flags: Komali's, piercing, has struck
local sx, sy, svx, svy, st, sn, sf, sid = {}, {}, {}, {}, {}, {}, {}, {}
for n = 1, MAX do sx[n], sy[n], svx[n], svy[n], st[n], sn[n], sf[n], sid[n] = 0, 0, 0, 0, 0, 0, 0, 0 end
local alive, ids = 0, 1000000          -- ids apart from fight.lua's blows

function shots.fire(x, y, vx, vy, life, n, mine, heavy)
  if alive >= MAX then return end
  alive = alive + 1
  ids = ids + 1
  sx[alive], sy[alive], svx[alive], svy[alive], st[alive] = x, y, vx, vy, life
  sn[alive], sf[alive], sid[alive] = n, (mine and MINE or 0) | (heavy and HEAVY or 0), ids
end

local function gone(n)                 -- the last one alive takes its place
  local a = alive
  sx[n], sy[n], svx[n], svy[n], st[n], sn[n], sf[n], sid[n] =
    sx[a], sy[a], svx[a], svy[a], st[a], sn[a], sf[a], sid[a]
  alive = a - 1
end

function shots.update(body, shadows)
  local k, struck, heavy = body.k, 0, false
  local n = 1
  while n <= alive do
    local x, y = sx[n] + svx[n], sy[n] + svy[n]
    sx[n], sy[n], st[n] = x, y, st[n] - 1
    local done = st[n] <= 0 or move.blocked(x, y, 1, 1)
    local f = sf[n]
    local pierce = f & HEAVY ~= 0
    if not done and f & MINE ~= 0 then
      for _, s in ipairs(shadows.list) do
        if s.on and s.hit ~= sid[n] and x >= s.x and x < s.x + s.w and y >= s.y and y < s.y + s.h then
          s.hit = sid[n]
          local r = shadows.strike(s, sn[n], svx[n] < 0 and -1 or 1, pierce)
          if r then
            if r ~= "blocked" then
              struck, heavy = struck + 1, heavy or pierce
              if f & GOT == 0 then f, shots.streak = f | GOT, shots.streak + 1 end
            end
            if not pierce or r == "blocked" then done = true break end
          end
        end
      end
      sf[n] = f
    elseif not done and f & MINE == 0 and x >= k.x and x < k.x + k.w and y >= k.y and y < k.y + k.h then
      local side = svx[n] > 0 and -1 or 1                      -- the side it comes from
      if k.guard < 0 and side == k.face then
        fx.spark(x, y)                                         -- on the shield
        done = true
      elseif body.hurt(math.max(1, math.floor(sn[n] * shadows.soft + 0.5)), k.x + k.w / 2 + side) then
        shadows.hits = shadows.hits + 1
        done = true
      end
    end
    if done and f & MINE ~= 0 and f & GOT == 0 then shots.streak = 0 end   -- it missed
    if done then gone(n) else n = n + 1 end
  end
  return struck, heavy
end

-- an arrow: its shaft, a bright head, red fletching
function shots.draw()
  for n = 1, alive do
    local vx, vy = svx[n], svy[n]
    local len = math.sqrt(vx * vx + vy * vy)
    local ux, uy = vx / len, vy / len
    local x, y = sx[n], sy[n]
    local heavy = sf[n] & HEAVY ~= 0
    line(x - ux * 8, y - uy * 8, x - ux, y - uy, sf[n] & MINE ~= 0 and C.tan or C.wood)
    pset(x, y, heavy and C.lamp or C.glow)
    line(x - ux * 9, y - uy * 9 - 1, x - ux * 8, y - uy * 8 - 1, C.red)
    if heavy and stat("frame") % 4 < 2 then pset(x - ux * 4, y - uy * 4, C.lamp) end
  end
end

function shots.clear() alive = 0 end
function shots.count() return alive end

return shots
