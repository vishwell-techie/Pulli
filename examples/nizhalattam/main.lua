-- Nizhalattam (நிழலாட்டம், "shadow play"): Pulli's platformer showcase.
--
-- A cracked clown puppet, Komali, steps through the cloth screen of a
-- shadow-puppet theatre into the world of its stories, and wears the roles
-- of the other puppets to bring them home. So far: the Courtyard; the first
-- story, the Screen, a lesson a room, with Veeran as its boss; and the
-- second, the Painted Forest, with Vil.
--
--   body.lua      how Komali moves: running, jumping, dodging, walls, blows
--   fight.lua     his roles and his blows; the freeze and the shake
--   shots.lua     arrows in flight, his and the shadows' (only where wanted)
--   shadows.lua   the enemies: soldier, dummy, inkblot, scrap
--   forest.lua    the forest's own: vine-hand, leaf-moth, wisp (in its rooms only)
--   veeran.lua    Veeran, the Screen's boss (loaded in his room only)
--   vil.lua       Vil, the forest's boss (loaded in his room only)
--   rooms.lua     rooms and the doors between them; reading ahead
--   stall.lua     the stall, where mai is spent (loaded in its rooms only)
--   box.lua       the Aasaan's box: repairs, the roles to carry, a seed
--   pick.lua      choosing roles: at the box, the halfway tear, a role lent
--   run.lua       what is kept between runs, and what a run carries
--   lines.lua     every word, in Tamil and English
--   fx.lua        scraps, sparks, and the drops of ink (mai)
--
-- A frame starts from the place's still background (backdrop), then is
-- drawn in passes, a sprite sheet each: the room's tiles from its sheet,
-- then Komali, the shadows and the things in the room from theirs
-- (sheet.load). START pauses; in the pause SELECT changes the
-- language. SELECT while playing shows the numbers.

local body    = require("body")
local fight   = require("fight")
local shadows = require("shadows")
local fx      = require("fx")
local rooms   = require("rooms")
local run     = require("run")
local lines   = require("lines")
local text    = require("text")
local C       = require("colours")

local cam = { x = 0, y = 0 }
local show = false
local mode = "play"                     -- "play", "pause" or "card"
local card, card2, card_t, card_then = nil, nil, 0, nil
local toast, toast_t = nil, 0
local hint, hint2, hint_for = nil, nil, nil
local CARD = 150                        -- frames a card shows (A skips after a second)

local function home()
  run.begin(body)
  rooms.enter("map.ooru", nil, body)
  body.k.health = body.k.max
  cam.x, cam.y = body.k.x - 160, 0
end

function init()
  -- collect sooner than Lua's default (when the heap has doubled): the game
  -- keeps little garbage, and the room it leaves is the 256 KB heap's
  collectgarbage("incremental", 120, 200)
  run.load()
  preload(rooms.ACTORS)
  home()
end

local function show_card(a, b, after, c)
  -- broken into lines that fit: the first line large, the rest small
  font()
  a = table.concat(text.wrap(a, 34), "\n")
  font("small")
  b = b and table.concat(text.wrap(b, 36), "\n")
  if c then b = (b and b .. "\n" or "") .. c end
  font()
  mode, card, card2, card_t, card_then = "card", a, b, CARD, after
end

local function say(s)                  -- broken into lines that fit, in the small size
  font("small")
  toast, toast_t = table.concat(text.wrap(s, 36), "\n"), 180
  font()
end

-- how the run went: its seed, its time, the stories cleared
local function summary()
  return lines.t("summary", string.format("%05d", run.seed or 0), run.clock(), run.cleared, #run.order)
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

-- the room's hint, worked out once a room (and again if the language changes)
local function hints()
  local key = rooms.name .. lines.lang
  if hint_for == key then return end
  hint_for = key
  local def = rooms.def()
  local function make(h, keys)
    if not h then return nil end
    local b = {}
    for name in (keys or ""):gmatch("%S+") do b[#b + 1] = buttons[name] end
    return lines.t(h, table.unpack(b))
  end
  hint, hint2 = make(def.hint, def.keys), make(def.hint2, def.keys2)
  -- broken into lines that fit, in the small size they are drawn at
  font("small")
  hint = hint and table.concat(text.wrap(hint, 36), "\n")
  hint2 = hint2 and table.concat(text.wrap(hint2, 36), "\n")
  font()
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
  local shop, pk = rooms.shop, rooms.pick
  if shop and shop.update(i, body) then return end
  if pk and pk ~= shop and pk.update(i, body) then return end
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
  run.time = run.time + 1
  if rooms.update(i, body) then          -- through a door: the world waits
    if rooms.started then                -- into the first story: the run begins
      rooms.started = false
      run.start(body, rooms.MIDDLE)
      if run.typed then say(lines.t("seeded")) end
    end
    if rooms.ended then
      rooms.ended = false
      if not run.typed then run.data.played = run.data.played + 1 run.keep() end
      show_card(lines.t("done"), nil, home, summary())
      return
    end
    cam.x, cam.y = body.k.x + 5 - 160, body.k.y + 10 - 140
    follow()
    return
  end
  if shop and i.door and rooms.near(rooms.shop_x, body.k) then shop.open() return end

  local before = body.k.health
  body.k.pit_free = run.charm("spool")
  body.update(i)
  fight.update(i, body, shadows)
  shadows.update(body)
  if body.k.health < before then fight.hit(false) end   -- struck: the world stops too
  -- Veeran is too big to pass through, rolling or not: Komali is pushed
  -- back out to the side he came from, and bounces off his crown
  local b = shadows.boss
  if b and b.on and shadows.overlap(b.x, b.y, b.w, b.h, body.k) then
    local k = body.k
    if k.vy > 0 and k.y + k.h - k.vy <= b.y + 2 then
      k.y, k.vy = b.y - k.h, -2.6
    else
      local left = k.x + k.w / 2 < b.x + b.w / 2
      require("move").by(k, left and (b.x - k.w - k.x) or (b.x + b.w - k.x), 0)
      k.vx = 0
    end
  end
  fight.mai = fight.mai + fx.update(body.k)
  follow()
  -- the boss torn: his role lent, and oil
  local b = shadows.boss
  if shadows.beaten and b then
    shadows.beaten = false
    run.cleared = run.cleared + 1
    -- both places full: which role to give up for his, if any
    local full = #fight.carried >= 3
    for _, r in ipairs(fight.carried) do if r.name:lower() == b.role then full = false end end
    run.lent[b.role] = true
    if full then rooms.want("pick").open("lend", b.role) else fight.lend(b.role) end
    run.add_oil(b.oil)
    say(full and lines.t("oil", b.oil) or lines.t("lent", lines.role(fight.ROLES[b.role].name)) .. "   " .. lines.t("oil", b.oil))
    -- what his role does, in place of the room's hint
    local def = rooms.def()
    local keys = {}
    for key in def.tkeys:gmatch("%S+") do keys[#keys + 1] = buttons[key] end
    font("small")
    hint, hint2 = table.concat(text.wrap(lines.t(def.taught, table.unpack(keys)), 36), "\n"), nil
    font()
  end
  -- fallen: the run ends; he wakes on the Aasaan's box
  if body.k.health <= 0 then
    if not run.typed then run.data.falls = run.data.falls + 1 run.keep() end
    show_card(lines.t("fallen"), lines.t("woke"), home, run.seed and summary())
  end
end

-- The HUD, on a strip of dark leather along the top: health, the roles
-- carried (the worn one lit), the skill's wait, mai, and oil at home.
local function hud()
  local k, role = body.k, fight.role()
  font("small")
  rectfill(0, 0, 320, 18, C.deep)
  line(0, 18, 319, 18, C.marigold)
  line(0, 19, 319, 19, C.ink)
  rectfill(4, 5, 64, 8, C.ink)
  rectfill(6, 7, 60 * k.health // k.max, 4, k.health > 30 and C.saffron or C.red)
  line(6, 7, 5 + 60 * k.health // k.max, 7, k.health > 30 and C.lamp or C.vermil)
  print(k.health, 72, 4, C.cloth)
  -- the role worn, by name; a bead for each carried, the worn one lit
  print(lines.role(role.name), 100, 4, C.lamp)
  for n = 1, #fight.carried do circfill(186 + n * 9, 9, 2, n == fight.worn and C.lamp or C.tan) end
  local wait = fight.cooldown()
  if wait > 0 then rectfill(100, 15, 40 * wait // role.wait, 2, C.sky) end
  spr(790, 232, 5)
  print(fight.mai, 243, 4, C.cloth)
  if rooms.name == "map.ooru" then
    spr(791, 278, 5)
    print(run.data.oil, 289, 4, C.lamp)
  end
  -- the boss's health, along the bottom
  local b = shadows.boss
  if b and b.on then
    rectfill(58, 226, 204, 10, C.ink)
    rect(58, 226, 204, 10, C.marigold)
    rectfill(60, 228, 200 * b.hp // b.max, 6, C.red)
    line(60, 228, 59 + 200 * b.hp // b.max, 228, C.vermil)
  end
  font()
end

-- text ringed in ink, so it reads on the bright cloth and on the night;
-- each line centred
local function say_at(s, y, c)
  for l in s:gmatch("[^\n]+") do
    text.outline(l, 160 - text.width(l) // 2, y, c, C.ink)
    y = y + text.height(l) + 2
  end
  return y
end

local function overlay()
  font("small")
  if hint and mode == "play" and not (rooms.shop and rooms.shop.is_open()) and not (rooms.pick and rooms.pick.is_open()) then
    local y = say_at(hint, 28, C.glow)
    if hint2 then say_at(hint2, y + 2, C.cloth) end
  end
  if toast_t > 0 then say_at(toast, toast:find("\n") and 184 or 196, C.lamp) end
  if mode == "pause" then
    rectfill(30, 30, 260, 180, C.deep)
    rect(30, 30, 260, 180, C.marigold)
    rect(32, 32, 256, 176, C.wood)
    font()
    text.center(lines.t("paused"), 42, C.lamp)
    font("small")
    local y = 64
    local names = ""
    for n, r in ipairs(fight.carried) do names = names .. (n > 1 and ", " or "") .. lines.role(r.name) end
    print(lines.t("roles") .. ": " .. names, 44, y, C.cloth)
    y = y + 20
    local cs = ""
    for n, c in ipairs(run.charms) do cs = cs .. (n > 1 and ", " or "") .. lines.t(c) end
    print(lines.t("charms") .. ": " .. (cs == "" and "-" or cs), 44, y, C.cloth)
    y = y + 20
    print(lines.t("mai") .. ": " .. fight.mai .. "    " .. lines.t("oil_k") .. ": " .. run.data.oil, 44, y, C.cloth)
    if run.seed then
      y = y + 20
      print(summary(), 44, y, C.cloth)
      if run.typed then print(lines.t("seeded"), 44, y + 16, C.vermil) end
    end
    text.center(lines.t("resume", buttons.start, buttons.select), 186, C.tan)
  end
  if mode == "card" then
    cls(C.ink)
    font()
    local y = say_at(card, 96, C.lamp)
    if card2 then
      font("small")
      say_at(card2, y + 8, C.tan)
    end
  end
  font()
end

function draw()
  local fade = rooms.fade()
  if fade > 0.66 then cls(C.ink) return end
  if fade > 0.33 then for c = 0, 31 do pal(c, c + 32) end end   -- half dark
  hints()
  -- the frame starts from the place's background (backdrop, set by
  -- rooms.lua), still while the room moves over it
  local def = rooms.def()
  cls()
  local sx = fight.shake_px > 0 and math.random(-fight.shake_px, fight.shake_px) or 0
  local sy = fight.shake_px > 0 and math.random(-fight.shake_px, fight.shake_px) or 0
  camera(math.floor(cam.x) + sx, math.floor(cam.y) + sy)
  -- pass 1: the room, from its tile sheet
  sheet.load(def.sheet)
  map.draw(0)
  rooms.draw_doors()
  -- pass 2: the things in it, the shadows and Komali, from theirs
  sheet.load(rooms.ACTORS)
  rooms.draw_things()
  shadows.draw()
  local role = fight.role()
  local pose = fight.pose(body)
  body.draw(role.colours, pose and body.FRAME[pose], role.frames)
  if fade > 0.33 then for c = 0, 31 do pal(c, c + 32) end end   -- body.draw resets pal
  fight.draw(body)
  if fight.shots then fight.shots.draw() end
  fx.draw()
  camera()
  hud()
  if rooms.shop then rooms.shop.draw(body) end
  if rooms.pick and rooms.pick ~= rooms.shop then rooms.pick.draw() end
  overlay()
  if show then
    local k = body.k
    rectfill(0, 214, 320, 26, C.ink)
    print(string.format("vx %5.2f vy %5.2f %s  jump %.1f tiles", k.vx, k.vy,
          k.ground and "ground" or "air " .. k.air, k.peak / 8), 4, 216, C.glow)
    print(string.format("dodge %2d wait %2d buf %d struck %2d", k.dodge, k.wait, k.buf, k.struck), 4, 228, C.tan)
  end
  pal()
end
