-- fight.lua — Komali's roles and his blows; the freeze and the shake that
-- make a blow feel solid.
--
--   fight.wear({ "komali", "veeran" })   the roles he carries; the first is worn
--                                        (komali, veeran, vil, aattakkaari)
--   fight.lend("veeran")                 a role lent for the rest of the run
--   fight.sharp, fight.charms            set by run.lua: roles sharpened, charms
--   fight.first                          no blow has landed in this room yet
--                                        (rooms.lua sets it: the torn page)
--   fight.update(input, body, shadows)   once a frame, after body.update
--   fight.draw(body)                     his blow, over him
--   fight.arrows(wanted)                 arrows (shots.lua) kept while the room
--                                        wants them or a role carried shoots;
--                                        fight.shots is then the module
--   fight.freeze, fight.shake_px         read by main.lua: frames the world
--                                        stands still, and how far it shakes
--
-- B strikes: a combo of three, the next one if B is pressed again in time.
-- In the air it is the role's air blow. The warrior, B held after a blow,
-- gathers a heavy slash, let go when it shines. X is the role's skill. L and
-- R change role, and the role coming in strikes as it comes (heavy: it
-- breaks a guard). A blow that lands stops the world for a few frames.
-- The archer looses arrows instead (shots.lua): B, aimed with up or down;
-- B held, a piercing arrow; X, a rain of arrows on a spot ahead; coming in,
-- a leap back, loosing three down at what is in front. Each arrow that
-- strikes makes the next fly further, until one misses.
-- The dancer kicks, each kick carrying her on; X dashes through the
-- shadows in her way, stunning them; a dodge leaves a ring that strikes.

local move  = require("move")
local C     = require("colours")
local fx    = require("fx")

local fight = { freeze = 0, shake_px = 0, shake_t = 0, worn = 1, carried = {}, swing = 0,
                mai = 0,         -- the ink picked up this run
                sharp = {}, charms = {} }

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
}
-- The other roles are in their own files (role_veeran.lua, role_vil.lua, ...),
-- read when first worn or lent, and let go when no longer carried.
local FILE = "role_"                   -- (a name made, so pack does not take "role_" for a module)
setmetatable(ROLES, { __index = function(t, name)
  local r = require(FILE .. name)
  rawset(t, name, r)
  return r
end })
fight.ROLES = ROLES

local CHARGE = 30        -- frames B is held for the heavy slash
local CHAIN = 15         -- frames after a blow in which B carries the combo on
local PRATFALL, BASH, TRIP = 30, 24, 60

local atk, f, step, queued, idle, charge, cool, skill_t = nil, 0, 0, false, 99, 0, 0, 0
local aim = 0                          -- the archer's aim: -1 up, 1 down

function fight.wear(list)
  local c = fight.carried
  for n = #c, 1, -1 do c[n] = nil end
  for name in pairs(ROLES) do                -- roles no longer carried are let go
    local kept = name == "komali"
    for _, r in ipairs(list) do kept = kept or r == name end
    if not kept then ROLES[name] = nil unrequire(FILE .. name) end
  end
  for n, r in ipairs(list) do
    c[n] = ROLES[r]
    if c[n].sheet then preload(c[n].sheet) end      -- its frames on a sheet of its own
  end
  fight.arrows(false)
  fight.worn = 1
  atk, step, charge, cool, skill_t = nil, 0, 0, 0, 0
end

function fight.role() return fight.carried[fight.worn] end

-- The frame Komali shows for what he is doing (body.FRAME), or nil.
function fight.pose(body)
  local role = fight.role()
  local p = role.poses                       -- a role with frames for its blows alone
  if p then
    if skill_t > 0 then return p.skill end
    if not atk then return nil end
    if atk == role.swap then return p.swap end
    if atk == role.air then return p.air end
    if atk then return p[step] or p[1] end
    return nil
  end
  if role.bow then
    if skill_t > 0 then return "rain" end
    if atk == role.swap then return "leap" end
    if atk or charge > 0 then
      if not body.k.ground then return "air" end
      return aim < 0 and "aim_up" or aim > 0 and "aim_down" or "aim"
    end
    return nil
  end
  if skill_t > 0 then return role.skill == "pratfall" and "flat" or "slap1" end
  if atk then
    if atk == role.swap then return role.name == "Komali" and "cart" or "slap3" end
    if atk == role.air then return "spin" end
    if atk == role.heavy then return "slap3" end
    return step == 2 and "slap2" or step == 3 and "slap3" or "slap1"
  end
  if charge >= CHARGE then return "gather" end
end

-- A role lent: carried for the rest of the run, beside his own and at most
-- one more. (Choosing which to give up when both places are full comes
-- with the roles chosen at the Aasaan's box.)
function fight.lend(name)
  local c = fight.carried
  for _, r in ipairs(c) do if r == ROLES[name] then return false end end
  if #c >= 3 then c[3] = ROLES[name] else c[#c + 1] = ROLES[name] end
  if ROLES[name].sheet then preload(ROLES[name].sheet) end
  if ROLES[name].bow then fight.arrows(true) end
  return true
end

function fight.arrows(wanted)
  local need = wanted
  for _, r in ipairs(fight.carried) do need = need or r.bow end
  if fight.shots then fight.shots.clear() end
  if need and not fight.shots then fight.shots = require("shots")
  elseif not need and fight.shots then fight.shots = nil unrequire("shots") end
end

-- Both places full, a lent role taken in place of one carried: that one
-- is let go.
function fight.give_up(old, new)
  local c, was = fight.carried, rawget(ROLES, old)
  for n = 2, #c do if c[n] == was then c[n] = ROLES[new] end end
  ROLES[old] = nil
  unrequire(FILE .. old)
  if ROLES[new].sheet then preload(ROLES[new].sheet) end
  fight.arrows(ROLES[new].bow)
end

local function has(charm)
  for _, c in ipairs(fight.charms) do if c == charm then return true end end
  return false
end

-- a blow's cost, with the role's edge, and the drum skin's
local function cost(n, role)
  local m = (fight.sharp[role.name] and 1.2 or 1) * (has("drum") and 1.15 or 1)
  return m == 1 and n or math.floor(n * m + 0.5)
end
fight.cost = cost
function fight.cooldown() return cool end
function fight.shorten(n) cool = math.max(0, cool - n) end      -- (the King's summons comes sooner)

-- a blow lands: the world stops for a moment, and shakes
function fight.hit(heavy)
  fight.freeze = math.max(fight.freeze, (heavy and 6 or 3) + (has("drum") and 2 or 0))   -- the drum skin: longer
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
  k.dodge_wait, k.guard, k.steady = role.dodge_wait, role.guard, role.steady or false

  -- a dodge or a blow taken ends any blow
  if k.dodge > 0 or k.struck > body.T.struck - 12 then atk, charge, skill_t = nil, 0, 0 end
  -- the bell anklet (and the dancer): a dodge leaves a ring that strikes
  if k.dodge == body.T.dodge - 1 and (has("bell") or role.ring) then
    fight.swing = fight.swing + 1
    fight.ring = 10
    for _, s in ipairs(shadows.list) do
      if s.on and shadows.overlap(k.x - 16, k.y, k.w + 32, k.h, s) then
        s.hit = fight.swing
        local r = shadows.strike(s, 6, s.x > k.x and 1 or -1, false)
        if r == "hit" or r == "torn" then fight.hit(false) end
      end
    end
  end
  if (fight.ring or 0) > 0 then fight.ring = fight.ring - 1 end

  -- change role: the one coming in strikes
  if i.swap ~= 0 and #fight.carried > 1 and k.struck == 0 then
    fight.worn = (fight.worn - 1 + i.swap) % #fight.carried + 1
    role = fight.role()
    k.dodge_wait, k.guard = role.dodge_wait, role.guard
    step, charge, skill_t = 0, 0, 0
    start(role.swap)
    if role.swap.leap then k.vy, k.vx, k.ground = -3.2, -k.face * 2.6, false end
    if role.on_swap then role.on_swap(k) end
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
    elseif role.start_skill then
      skill_t = role.start_skill(k)
      fight.swing = fight.swing + 1
    else
      skill_t = BASH
      fight.swing = fight.swing + 1
    end
  end
  if skill_t > 0 then
    skill_t = skill_t - 1
    if role.tick_skill and role.tick_skill(skill_t, role, k) == false then skill_t = 0 end   -- ended early
    if role.skill == "bash" then
      k.guard = -1                             -- the shield: nothing from the front
      move.by(k, k.face * 1.4, 0)
      for _, s in ipairs(shadows.list) do
        if s.on and s.hit ~= fight.swing and shadows.overlap(k.x + (k.face > 0 and k.w or -8), k.y, 8, k.h, s) then
          s.hit = fight.swing
          if shadows.strike(s, cost(8, role), k.face, true) then fight.hit(true) end
        end
      end
    end
  end

  -- B: the combo, the air blow, and the warrior's heavy slash
  if atk == nil and skill_t == 0 then
    idle = idle + 1
    if i.attack and role.bow then
      step, aim = 0, i.up and -1 or i.down and 1 or 0
      start(role.shot)
      charge = 0
    elseif i.attack then
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
    if role.bow and f < atk.s then aim = i.up and -1 or i.down and 1 or 0 end
    f = f + 1
    if atk.speed and f == atk.s then role.loose(k, atk, aim) end
    local x, y, w, h = reach(k, atk)
    if x then
      for _, s in ipairs(shadows.list) do
        if s.on and s.hit ~= fight.swing and shadows.overlap(x, y, w, h, s) then
          s.hit = fight.swing
          local dir = atk.around and (s.x > k.x and 1 or -1) or k.face
          local n = cost(atk.n, role)
          if fight.first and has("torn") then n = n * 2 end          -- the torn page: the room's first blow, double
          local r = shadows.strike(s, n, dir, atk.heavy)
          if r == "hit" or r == "torn" then fight.hit(atk.heavy) fight.first = false end
          if r == "torn" and has("soot") then                        -- lamp soot: it burns those near it
            for _, o in ipairs(shadows.list) do
              if o.on and not o.prop and o ~= shadows.boss and math.abs(o.x - s.x) < 32 and math.abs(o.y - s.y) < 24 then
                fx.spark(o.x + o.w / 2, o.y + 4)
                shadows.strike(o, 6, o.x > s.x and 1 or -1, false)
              end
            end
          end
        end
      end
    end
    if atk.push and f < atk.s + atk.a then move.by(k, k.face * atk.push, 0) end
    if f >= atk.s + atk.a + atk.r then
      local m = atk
      atk, idle = nil, 0
      if queued and role.bow and m == role.shot then
        start(role.shot)
      elseif queued and m ~= role.air and m ~= role.swap and step < 3 then
        step = step + 1
        start(role.combo[step])
      end
    end
  end
  -- arrows in flight: those that strike stop the world too
  if fight.shots then
    local struck, heavy = fight.shots.update(body, shadows)
    if struck > 0 then fight.hit(heavy) end
  end
  k.slow = ((atk or (role.bow and charge > 0)) and k.ground) and role.slow or (skill_t > 0 and 0 or 1)
  -- what a role leaves behind keeps going while it is carried (the Minister's snares)
  for _, r in ipairs(fight.carried) do if r.each then r.each(k, shadows) end end
end

-- the blow, drawn as the arc of a sword or a slap; the heavy slash shines
-- while it gathers
function fight.draw(body)
  local k, role = body.k, fight.role()
  local cx, cy = k.x + k.w / 2, k.y + k.h / 2
  if (fight.ring or 0) > 0 then circ(cx, cy, 26 - fight.ring, C.lamp) end
  if skill_t > 0 and role.draw_skill then role.draw_skill(k) end
  for _, r in ipairs(fight.carried) do if r.draw_each then r.draw_each(k) end end
  if charge >= CHARGE and stat("frame") % 4 < 2 then
    if role.bow then circ(cx + k.face * 10, cy - 4, 3, C.lamp) else circ(cx - k.face * 4, cy - 16, 3, C.glow) end
  end
  if not atk or atk.speed then return end
  local x, y, w, h = reach(k, atk)
  if not x then
    return
  end
  local col = atk.heavy and C.lamp or C.glow
  if role.fire then col = stat("frame") % 4 < 2 and C.saffron or C.vermil end   -- the Queen's lamp-fire
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
