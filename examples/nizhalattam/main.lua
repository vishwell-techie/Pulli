-- Nizhalattam (நிழலாட்டம், "shadow play"): Pulli's platformer showcase.
--
-- A cracked clown puppet steps through the cloth screen of a shadow-puppet
-- theatre, into the world of its stories. This is step 3: three rooms
-- joined by doors (the grey test room, a climb and an arena), each drawn
-- with its own tile sheet; Komali with his own role and the warrior's,
-- against cut-paper soldiers.
--
--   body.lua      how Komali moves: running, jumping, dodging, walls, blows
--   fight.lua     his roles and his blows; the freeze and the shake
--   shadows.lua   the enemies: the cut-paper soldier
--   fx.lua        scraps, sparks, and the drops of ink (mai)
--   rooms.lua     rooms and the doors between them; reading ahead
--
-- The test room (map.tmx) has steps two to six tiles high, a stack of thin
-- floors, a pit, a pillar to slide down, gaps of growing width, an arena
-- with three soldiers, and a door on to the climb (climb.tmx), which leads
-- to the arena (arena.tmx). SELECT shows the numbers.
--
-- A frame is drawn in passes, a sprite sheet each: the room's tiles from
-- its sheet, then Komali and the shadows from theirs (sheet.load).

local body    = require("body")
local fight   = require("fight")
local shadows = require("shadows")
local fx      = require("fx")
local rooms   = require("rooms")

local cam = { x = 0, y = 0 }
local show = false

local function begin()
  rooms.enter("map.ooru", nil, body)
  body.k.health = 100
  fight.wear({ "komali", "veeran" })
  cam.x = body.k.x - 160
end

function init()
  preload(rooms.ACTORS)
  begin()
end

-- The camera leads the way he faces, and follows up and down more slowly,
-- catching up at once when he lands.
local function follow()
  local k = body.k
  local want_x = k.x + 5 - 160 + k.face * 40
  cam.x = cam.x + (want_x - cam.x) * 0.08
  local want_y = k.y + 10 - 140
  cam.y = cam.y + (want_y - cam.y) * (k.ground and 0.15 or 0.05)
  cam.x = math.max(0, math.min(rooms.w - 320, cam.x))
  cam.y = math.max(0, math.min(rooms.h - 240, cam.y))
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

  if rooms.update(i, body) then          -- through a door: the world waits
    cam.x, cam.y = body.k.x + 5 - 160, body.k.y + 10 - 140
    follow()
    return
  end
  local before = body.k.health
  body.update(i)
  fight.update(i, body, shadows)
  shadows.update(body)
  if body.k.health < before then fight.hit(false) end   -- struck: the world stops too
  fight.mai = fight.mai + fx.update(body.k)
  follow()
  -- beaten: for now, the room begins again
  if body.k.health <= 0 then begin() end
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
  local fade = rooms.fade()
  if fade > 0.66 then cls(0) return end
  if fade > 0.33 then for c = 0, 31 do pal(c, c + 32) end end   -- half dark
  cls(17)
  local sx = fight.shake_px > 0 and math.random(-fight.shake_px, fight.shake_px) or 0
  local sy = fight.shake_px > 0 and math.random(-fight.shake_px, fight.shake_px) or 0
  camera(math.floor(cam.x) + sx, math.floor(cam.y) + sy)
  -- pass 1: the room, from its tile sheet
  sheet.load(rooms.def().sheet)
  map.draw(0)
  rooms.draw_doors()
  -- pass 2: Komali and the shadows, from theirs
  sheet.load(rooms.ACTORS)
  shadows.draw()
  body.draw(fight.role().colours)
  if fade > 0.33 then for c = 0, 31 do pal(c, c + 32) end end   -- body.draw resets pal
  fight.draw(body)
  fx.draw()
  camera()
  hud()
  pal()
  if show then
    local k = body.k
    rectfill(0, 214, 320, 26, 0)
    print(string.format("vx %5.2f vy %5.2f %s  jump %.1f tiles", k.vx, k.vy,
          k.ground and "ground" or "air " .. k.air, k.peak / 8), 4, 216, 7)
    print(string.format("dodge %2d wait %2d buf %d struck %2d", k.dodge, k.wait, k.buf, k.struck), 4, 228, 6)
  end
end
