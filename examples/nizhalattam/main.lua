-- Nizhalattam (நிழலாட்டம், "shadow play"): Pulli's platformer showcase.
--
-- A cracked clown puppet steps through the cloth screen of a shadow-puppet
-- theatre, into the world of its stories. This is step 2: Komali in a grey
-- test room, with his own role and the warrior's, against cut-paper
-- soldiers, for tuning how he moves and how a fight feels.
--
--   body.lua      how Komali moves: running, jumping, dodging, walls, blows
--   fight.lua     his roles and his blows; the freeze and the shake
--   shadows.lua   the enemies: the cut-paper soldier
--   fx.lua        scraps, sparks, and the drops of ink (mai)
--
-- The test room (map.tmx) has steps two to six tiles high, a stack of thin
-- floors, a pit, a pillar to slide down, gaps of growing width, and at its
-- far end an arena with three soldiers. SELECT shows the numbers.

local body    = require("body")
local fight   = require("fight")
local shadows = require("shadows")
local fx      = require("fx")

local cam = { x = 0, y = 0 }
local show = false
local MAP_W, MAP_H = 0, 0
local START, SOLDIER = 1000, 1001       -- markers on layer 1

local function begin()
  local w, h = map.size()
  MAP_W, MAP_H = w * 8, h * 8
  shadows.clear()
  fx.clear()
  local sx, sy = 40, 200
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      local m = map.get(1, cx, cy)
      if m == START then sx, sy = cx * 8 + 4, cy * 8 + 8 end
      if m == SOLDIER then shadows.add(cx * 8 + 4, cy * 8 + 8) end
      if m == START or m == SOLDIER then map.set(1, cx, cy, 0) end
    end
  end
  body.place(sx, sy)
  body.k.health = 100
  fight.wear({ "komali", "veeran" })
  cam.x = sx - 160
end

function init() begin() end

-- The camera leads the way he faces, and follows up and down more slowly,
-- catching up at once when he lands.
local function follow()
  local k = body.k
  local want_x = k.x + 5 - 160 + k.face * 40
  cam.x = cam.x + (want_x - cam.x) * 0.08
  local want_y = k.y + 10 - 140
  cam.y = cam.y + (want_y - cam.y) * (k.ground and 0.15 or 0.05)
  cam.x = math.max(0, math.min(MAP_W - 320, cam.x))
  cam.y = math.max(0, math.min(MAP_H - 240, cam.y))
end

-- buttons pressed while the world stands still are kept for after
local held_jump, held_dodge, held_attack, held_skill, held_swap = false, false, false, false, 0
local was_select = false
function update(dt)
  local i = body.read()
  local s = btn("select")
  if s and not was_select then show = not show end
  was_select = s
  if fight.freeze > 0 then
    fight.freeze = fight.freeze - 1
    held_jump, held_dodge = held_jump or i.jump, held_dodge or i.dodge
    held_attack, held_skill = held_attack or i.attack, held_skill or i.skill
    if i.swap ~= 0 then held_swap = i.swap end
    return
  end
  i.jump, i.dodge = i.jump or held_jump, i.dodge or held_dodge
  i.attack, i.skill = i.attack or held_attack, i.skill or held_skill
  if held_swap ~= 0 then i.swap = held_swap end
  held_jump, held_dodge, held_attack, held_skill, held_swap = false, false, false, false, 0

  local before = body.k.health
  body.update(i)
  fight.update(i, body, shadows)
  shadows.update(body)
  if body.k.health < before then fight.hit(false) end   -- struck: the world stops too
  fight.mai = fight.mai + fx.update(body.k)
  follow()
  -- beaten: for now, the room begins again
  if body.k.health <= 0 then
    map.load("map.ooru")
    begin()
  end
end

local function hud()
  local k, role = body.k, fight.role()
  rectfill(4, 4, 64, 8, 0)
  rectfill(6, 6, 60 * k.health // 100, 4, k.health > 30 and 11 or 8)
  print(k.health, 72, 4, 7)
  -- the roles carried, the worn one bright; the skill's wait under it
  local x = 100
  for n, r in ipairs(fight.carried) do
    print(r.name, x, 4, n == fight.worn and 10 or 5)
    x = x + #r.name * 8 + 8
  end
  local wait = fight.cooldown()
  if wait > 0 then rectfill(100, 13, 40 * wait // role.wait, 2, 12) end
  circfill(296, 8, 3, 1) pset(295, 7, 12)
  print(fight.mai, 302, 4, 7)
end

function draw()
  cls(17)
  local sx = fight.shake_px > 0 and math.random(-fight.shake_px, fight.shake_px) or 0
  local sy = fight.shake_px > 0 and math.random(-fight.shake_px, fight.shake_px) or 0
  camera(math.floor(cam.x) + sx, math.floor(cam.y) + sy)
  map.draw(0)
  shadows.draw()
  body.draw(fight.role().colours)
  fight.draw(body)
  fx.draw()
  map.draw(1)
  camera()
  hud()
  if show then
    local k = body.k
    rectfill(0, 214, 320, 26, 0)
    print(string.format("vx %5.2f vy %5.2f %s  jump %.1f tiles", k.vx, k.vy,
          k.ground and "ground" or "air " .. k.air, k.peak / 8), 4, 216, 7)
    print(string.format("dodge %2d wait %2d buf %d struck %2d", k.dodge, k.wait, k.buf, k.struck), 4, 228, 6)
  end
end
