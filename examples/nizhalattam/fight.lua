-- fight.lua — Komali's roles and his blows; the freeze and the shake that
-- make a blow feel solid.
--
--   fight.wear({ "komali", "veeran" })   the roles he carries; the first is worn
--   fight.update(input, body, shadows)   once a frame, after body.update
--   fight.draw(body)                     his blow, over him
--   fight.freeze, fight.shake_px         read by main.lua: frames the world
--                                        stands still, and how far it shakes
--
-- B strikes: a combo of three, the next one if B is pressed again in time.
-- In the air it is the role's air blow. The warrior, B held after a blow,
-- gathers a heavy slash, let go when it shines. X is the role's skill. L and
-- R change role, and the role coming in strikes as it comes (heavy: it
-- breaks a guard). A blow that lands stops the world for a few frames.

local move = require("move")

local fight = { freeze = 0, shake_px = 0, shake_t = 0, worn = 1, carried = {}, swing = 0,
                mai = 0 }        -- the ink picked up this run

-- A blow: frames before it can land (s), while it can (a), after (r);
-- what it costs (n); the box it strikes, in front of him (w x h); heavy
-- blows break a guard. `around` strikes on both sides; `push` moves him.
local ROLES = {
  komali = {
    name = "Komali",
    combo = { { s = 3, a = 3, r = 7, n = 6, w = 14, h = 12 },
              { s = 3, a = 3, r = 7, n = 6, w = 14, h = 12 },
              { s = 4, a = 4, r = 10, n = 10, w = 16, h = 14 } },
    air = { s = 2, a = 8, r = 4, n = 6, w = 12, h = 20, around = true },
    swap = { s = 0, a = 12, r = 4, n = 8, w = 12, h = 20, around = true, heavy = true, push = 2 },
    skill = "pratfall", wait = 240,
    slow = 0.5, dodge_wait = 0.5, guard = 0,         -- his own: quicker dodges
  },
  veeran = {
    name = "Veeran",
    colours = { 8, 12, 24, 28, 10, 6, 41, 38 },      -- blue costume, steel helmet
    combo = { { s = 5, a = 4, r = 10, n = 12, w = 20, h = 16 },
              { s = 5, a = 4, r = 10, n = 12, w = 20, h = 16 },
              { s = 7, a = 5, r = 14, n = 20, w = 22, h = 18 } },
    air = { s = 4, a = 5, r = 8, n = 12, w = 18, h = 22 },
    heavy = { s = 2, a = 6, r = 16, n = 40, w = 26, h = 20, heavy = true },
    swap = { s = 2, a = 6, r = 8, n = 18, w = 22, h = 24, heavy = true },
    skill = "bash", wait = 300,
    slow = 0.3, dodge_wait = 1, guard = 0.15,        -- takes 15% less from every blow
  },
}
fight.ROLES = ROLES

local CHARGE = 30        -- frames B is held for the heavy slash
local CHAIN = 15         -- frames after a blow in which B carries the combo on
local PRATFALL, BASH, TRIP = 30, 24, 60

local atk, f, step, queued, idle, charge, cool, skill_t = nil, 0, 0, false, 99, 0, 0, 0

function fight.wear(list)
  local c = fight.carried
  for n = #c, 1, -1 do c[n] = nil end
  for n, r in ipairs(list) do c[n] = ROLES[r] end
  fight.worn = 1
  atk, step, charge, cool, skill_t = nil, 0, 0, 0, 0
end

function fight.role() return fight.carried[fight.worn] end
function fight.cooldown() return cool end

-- a blow lands: the world stops for a moment, and shakes
function fight.hit(heavy)
  fight.freeze = math.max(fight.freeze, heavy and 6 or 3)
  fight.shake_px, fight.shake_t = heavy and 3 or 1, heavy and 10 or 4
end

local function start(m)
  atk, f, queued = m, 0, false
  fight.swing = fight.swing + 1
end

-- the box a blow strikes this frame, or nil
local function reach(k, m)
  if f < m.s or f >= m.s + m.a then return nil end
  local y = k.y + k.h / 2 - m.h / 2
  if m.around then return k.x + k.w / 2 - m.w, y, m.w * 2, m.h end
  return k.face > 0 and k.x + k.w or k.x - m.w, y, m.w, m.h
end

function fight.update(i, body, shadows)
  local k, role = body.k, fight.role()
  if fight.shake_t > 0 then fight.shake_t = fight.shake_t - 1 else fight.shake_px = 0 end
  if cool > 0 then cool = cool - 1 end
  k.dodge_wait, k.guard = role.dodge_wait, role.guard

  -- a dodge or a blow taken ends any blow
  if k.dodge > 0 or k.struck > body.T.struck - 12 then atk, charge, skill_t = nil, 0, 0 end

  -- change role: the one coming in strikes
  if i.swap ~= 0 and #fight.carried > 1 and k.struck == 0 then
    fight.worn = (fight.worn - 1 + i.swap) % #fight.carried + 1
    role = fight.role()
    k.dodge_wait, k.guard = role.dodge_wait, role.guard
    step, charge, skill_t = 0, 0, 0
    start(role.swap)
  end

  -- the skill
  if i.skill and cool == 0 and k.dodge == 0 and skill_t == 0 then
    cool, atk = role.wait, nil
    if role.skill == "pratfall" then
      skill_t = PRATFALL
      k.struck = PRATFALL                      -- flat on the floor: nothing touches him
      for _, s in ipairs(shadows.list) do
        if s.on and math.abs(s.x - k.x) < 40 and math.abs(s.y - k.y) < 24 then
          s.state, s.t, s.vx = "reel", TRIP, 0
        end
      end
    else
      skill_t = BASH
      fight.swing = fight.swing + 1
    end
  end
  if skill_t > 0 then
    skill_t = skill_t - 1
    if role.skill == "bash" then
      k.guard = -1                             -- the shield: nothing from the front
      move.by(k, k.face * 1.4, 0)
      for _, s in ipairs(shadows.list) do
        if s.on and s.hit ~= fight.swing and shadows.overlap(k.x + (k.face > 0 and k.w or -8), k.y, 8, k.h, s) then
          s.hit = fight.swing
          if shadows.strike(s, 8, k.face, true) then fight.hit(true) end
        end
      end
    end
  end

  -- B: the combo, the air blow, and the warrior's heavy slash
  if atk == nil and skill_t == 0 then
    idle = idle + 1
    if i.attack then
      if not k.ground then step = 0; start(role.air)
      else
        step = (idle <= CHAIN and step < 3) and step + 1 or 1
        start(role.combo[step])
      end
      charge = 0
    elseif role.heavy and i.b and k.ground then
      charge = charge + 1
    elseif charge > 0 then
      if charge >= CHARGE then start(role.heavy) end
      charge = 0
    end
  elseif atk then
    if i.attack then queued = true end
    f = f + 1
    local x, y, w, h = reach(k, atk)
    if x then
      for _, s in ipairs(shadows.list) do
        if s.on and s.hit ~= fight.swing and shadows.overlap(x, y, w, h, s) then
          s.hit = fight.swing
          local dir = atk.around and (s.x > k.x and 1 or -1) or k.face
          local r = shadows.strike(s, atk.n, dir, atk.heavy)
          if r == "hit" or r == "torn" then fight.hit(atk.heavy) end
        end
      end
    end
    if atk.push and f < atk.s + atk.a then move.by(k, k.face * atk.push, 0) end
    if f >= atk.s + atk.a + atk.r then
      local m = atk
      atk, idle = nil, 0
      if queued and m ~= role.air and m ~= role.swap and step < 3 then
        step = step + 1
        start(role.combo[step])
      end
    end
  end
  k.slow = (atk and k.ground) and role.slow or (skill_t > 0 and 0 or 1)
end

-- the blow, drawn as the arc of a sword or a slap; the heavy slash shines
-- while it gathers
function fight.draw(body)
  local k, role = body.k, fight.role()
  local cx, cy = k.x + k.w / 2, k.y + k.h / 2
  if charge >= CHARGE and stat("frame") % 4 < 2 then circ(cx + k.face * 10, cy - 4, 3, 10) end
  if not atk then return end
  local x, y, w, h = reach(k, atk)
  if not x then
    if role.name == "Veeran" then line(cx, cy, cx - k.face * 6, cy - 10, 6) end   -- raised
    return
  end
  local col = atk.heavy and 10 or 7
  local r = atk.around and atk.w or atk.w
  local p = (f - atk.s) / atk.a
  for n = 0, 4 do
    local a0 = -1.2 + p * 2.4 * n / 4
    local a1 = a0 + 0.5
    local d = atk.around and 1 or k.face
    line(cx + d * math.cos(a0) * r, cy + math.sin(a0) * h / 2,
         cx + d * math.cos(a1) * r, cy + math.sin(a1) * h / 2, col)
    if atk.around then
      line(cx - math.cos(a0) * r, cy + math.sin(a0) * h / 2,
           cx - math.cos(a1) * r, cy + math.sin(a1) * h / 2, col)
    end
  end
end

return fight
