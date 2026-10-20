-- Nizhalattam (நிழலாட்டம், "shadow play"): Pulli's platformer showcase.
--
-- A cracked clown puppet, Komali, steps through the cloth screen of a
-- shadow-puppet theatre into the world of its stories, and wears the roles
-- of the other puppets to bring them home. This is step 4, the first
-- playable: the Courtyard, and the first story, the Screen, a lesson a
-- room, the stall, and Veeran as its boss.
--
--   body.lua      how Komali moves: running, jumping, dodging, walls, blows
--   fight.lua     his roles and his blows; the freeze and the shake
--   shadows.lua   the enemies: soldier, dummy, inkblot, scrap
--   veeran.lua    Veeran, the Screen's boss (loaded in his room only)
--   rooms.lua     rooms and the doors between them; reading ahead
--   stall.lua     the stall, where mai is spent
--   run.lua       what is kept between runs, and what a run carries
--   lines.lua     every word, in Tamil and English
--   fx.lua        scraps, sparks, and the drops of ink (mai)
--
-- A frame is drawn in passes, a sprite sheet each: the room's tiles from
-- its sheet, then Komali, the shadows and the things in the room from
-- theirs (sheet.load). START pauses; in the pause SELECT changes the
-- language. SELECT while playing shows the numbers.

local body    = require("body")
local fight   = require("fight")
local shadows = require("shadows")
local fx      = require("fx")
local rooms   = require("rooms")
local stall   = require("stall")
local run     = require("run")
local lines   = require("lines")
local text    = require("text")

local cam = { x = 0, y = 0 }
local show = false
local mode = "play"                     -- "play", "pause" or "card"
local card, card2, card_t, card_then = nil, nil, 0, nil
local toast, toast_t = nil, 0
local hint, hint2, hint_for = nil, nil, nil
local CARD = 150                        -- frames a card shows (A skips after a second)

local function home()
  run.begin()
  rooms.enter("map.ooru", nil, body)
  body.k.health = 100
  cam.x, cam.y = body.k.x - 160, 0
end

function init()
  run.load()
  preload(rooms.ACTORS)
  home()
end

local function show_card(a, b, after)
  mode, card, card2, card_t, card_then = "card", a, b, CARD, after
end

local function say(s) toast, toast_t = s, 180 end

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

-- the room's hint, worked out once a room (and again if the language changes)
local function hints()
  local key = rooms.name .. lines.lang
  if hint_for == key then return end
  hint_for = key
  local def = rooms.def()
  local function make(h, keys)
    if not h then return nil end
    local b = {}
    for n, name in ipairs(keys or {}) do b[n] = buttons[name] end
    return lines.t(h, table.unpack(b))
  end
  hint, hint2 = make(def.hint, def.keys), make(def.hint2, def.keys2)
end

-- buttons pressed while the world stands still are kept for after
local held_jump, held_dodge, held_attack, held_skill, held_swap = false, false, false, false, 0
local was_select = false

function update(dt)
  local i = body.read()
  local sel = btn("select")
  local select_p = sel and not was_select
  was_select = sel
  if toast_t > 0 then toast_t = toast_t - 1 end

  if mode == "card" then
    card_t = card_t - 1
    if card_t <= 0 or (card_t < CARD - 60 and i.jump) then
      mode = "play"
      if card_then then card_then() end
    end
    return
  end
  if mode == "pause" then
    if i.pause then mode = "play" end
    if select_p then
      lines.use(lines.lang == "ta" and "en" or "ta")
      run.data.lang = lines.lang
      run.keep()
    end
    return
  end
  if stall.update(i, body) then return end
  if select_p then show = not show end

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

  if i.pause then mode = "pause" return end
  if rooms.update(i, body) then          -- through a door: the world waits
    if rooms.ended then
      rooms.ended = false
      run.data.screen_played = run.data.screen_played + 1
      run.keep()
      show_card(lines.t("done"), nil, home)
      return
    end
    cam.x, cam.y = body.k.x + 5 - 160, body.k.y + 10 - 140
    follow()
    return
  end
  if i.door and rooms.near(rooms.stall_x, body.k) then stall.open() return end

  local before = body.k.health
  body.k.pit_free = run.charm("spool")
  body.update(i)
  fight.update(i, body, shadows)
  shadows.update(body)
  if body.k.health < before then fight.hit(false) end   -- struck: the world stops too
  fight.mai = fight.mai + fx.update(body.k)
  follow()
  -- the boss torn: his role lent, and oil
  local b = shadows.boss
  if shadows.beaten and b then
    shadows.beaten = false
    fight.lend(b.role)
    run.add_oil(b.oil)
    say(lines.t("lent") .. "   " .. lines.t("oil", b.oil))
    hint, hint2 = lines.t("h_swap", buttons.l, buttons.r), nil
  end
  -- fallen: the run ends; he wakes on the Aasaan's box
  if body.k.health <= 0 then
    run.data.falls = run.data.falls + 1
    run.keep()
    show_card(lines.t("fallen"), lines.t("woke"), home)
  end
end

local function hud()
  local k, role = body.k, fight.role()
  font("small")
  rectfill(4, 4, 64, 8, 0)
  rectfill(6, 6, 60 * k.health // 100, 4, k.health > 30 and 11 or 8)
  print(k.health, 72, 3, 7)
  -- the roles carried, the worn one bright; the skill's wait under it
  local x = 100
  for n, r in ipairs(fight.carried) do
    local name = lines.role(r.name)
    print(name, x, 3, n == fight.worn and 10 or 5)
    x = x + text.width(name) + 8
  end
  local wait = fight.cooldown()
  if wait > 0 then rectfill(100, 15, 40 * wait // role.wait, 2, 12) end
  circfill(272, 8, 3, 1) pset(271, 7, 12)
  print(fight.mai, 278, 3, 7)
  if rooms.name == "map.ooru" then
    circfill(272, 22, 3, 9)
    print(run.data.oil, 278, 17, 7)
  end
  -- the boss's health, along the bottom
  local b = shadows.boss
  if b and b.on then
    rectfill(60, 228, 200, 6, 0)
    rectfill(61, 229, 198 * b.hp // b.max, 4, 8)
  end
  font()
end

local function overlay()
  font("small")
  if hint and mode == "play" and not stall.is_open() then
    text.center(hint, 26, 7)
    if hint2 then text.center(hint2, 26 + text.height(hint) + 4, 6) end
  end
  if toast_t > 0 then text.center(toast, 200, 10) end
  if mode == "pause" then
    rectfill(30, 30, 260, 180, 0)
    rect(30, 30, 260, 180, 9)
    font()
    text.center(lines.t("paused"), 40, 10)
    font("small")
    local y = 64
    local names = ""
    for n, r in ipairs(fight.carried) do names = names .. (n > 1 and ", " or "") .. lines.role(r.name) end
    print(lines.t("roles") .. ": " .. names, 44, y, 7)
    y = y + 20
    local cs = ""
    for n, c in ipairs(run.charms) do cs = cs .. (n > 1 and ", " or "") .. lines.t(c) end
    print(lines.t("charms") .. ": " .. (cs == "" and "-" or cs), 44, y, 7)
    y = y + 20
    print(lines.t("mai") .. ": " .. fight.mai .. "    " .. lines.t("oil_k") .. ": " .. run.data.oil, 44, y, 7)
    text.center(lines.t("resume", buttons.start, buttons.select), 186, 6)
  end
  if mode == "card" then
    cls(0)
    font()
    text.center(card, 100, 7)
    if card2 then
      font("small")
      text.center(card2, 100 + text.height(card) + 10, 6)
    end
  end
  font()
end

function draw()
  local fade = rooms.fade()
  if fade > 0.66 then cls(0) return end
  if fade > 0.33 then for c = 0, 31 do pal(c, c + 32) end end   -- half dark
  hints()
  cls(17)
  local sx = fight.shake_px > 0 and math.random(-fight.shake_px, fight.shake_px) or 0
  local sy = fight.shake_px > 0 and math.random(-fight.shake_px, fight.shake_px) or 0
  camera(math.floor(cam.x) + sx, math.floor(cam.y) + sy)
  -- pass 1: the room, from its tile sheet
  sheet.load(rooms.def().sheet)
  map.draw(0)
  rooms.draw_doors()
  -- pass 2: the things in it, the shadows and Komali, from theirs
  sheet.load(rooms.ACTORS)
  rooms.draw_things()
  shadows.draw()
  body.draw(fight.role().colours)
  if fade > 0.33 then for c = 0, 31 do pal(c, c + 32) end end   -- body.draw resets pal
  fight.draw(body)
  fx.draw()
  camera()
  hud()
  stall.draw(body)
  overlay()
  if show then
    local k = body.k
    rectfill(0, 214, 320, 26, 0)
    print(string.format("vx %5.2f vy %5.2f %s  jump %.1f tiles", k.vx, k.vy,
          k.ground and "ground" or "air " .. k.air, k.peak / 8), 4, 216, 7)
    print(string.format("dodge %2d wait %2d buf %d struck %2d", k.dodge, k.wait, k.buf, k.struck), 4, 228, 6)
  end
  pal()
end
