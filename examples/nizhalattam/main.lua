-- Nizhalattam (நிழலாட்டம், "shadow play"): Pulli's platformer showcase.
--
-- A cracked clown puppet, Komali, steps through the cloth screen of a
-- shadow-puppet theatre into the world of its stories, and wears the roles
-- of the other puppets to bring them home. So far: the Courtyard; the first
-- story, the Screen, a lesson a room, with Veeran as its boss; and the
-- second, the Painted Forest, with the Archer; the Leather Sea, with the
-- Dancer; the Battlefield of Flags, with the Elephant; the Market of
-- Masks, with the Minister; and last the Lamp Palace, with the Queen and
-- the Puppet King, who lets one puppet go when he is beaten.
--
--   body.lua      how Komali moves: running, jumping, dodging, walls, blows
--   fight.lua     his roles and his blows; the freeze and the shake
--   shots.lua     arrows in flight, his and the shadows' (only where wanted)
--   shadows.lua   the enemies: soldier, dummy, inkblot, scrap
--   forest.lua    the forest's own: vine-hand, leaf-moth, wisp (in its rooms only)
--   sea.lua       the sea's own: crab-shield, wave-cutter, gull; boats (in its rooms only)
--   flags.lua     the battlefield's own: archer line, flag-bearer, war drum (in its rooms only)
--   masks.lua     the market's own: mask thief, juggler, twin masks (in its rooms only)
--   palace.lua    the palace's own: lamp guard, mirror shade, cinder (in its rooms only)
--   veeran.lua    Veeran, the Screen's boss (loaded in his room only)
--   vil.lua       Vil, the forest's boss (loaded in his room only)
--   aattakkaari.lua  Aattakkaari, the sea's boss (loaded on her deck only)
--   yaanai.lua    the Elephant, the battlefield's boss (loaded in his field only)
--   mandhiri.lua  the Minister, the market's boss, and his decoys (in his court only)
--   rani.lua      the Queen, the palace's boss (in her hall only)
--   king.lua      the Puppet King, in three acts (on his stage only)
--   rooms.lua     rooms and the doors between them; reading ahead
--   stall.lua     the stall, where mai is spent (loaded in its rooms only)
--   box.lua       the Aasaan's box: repairs, the roles to carry, a seed
--   pick.lua      choosing roles: at the box, the halfway tear, a role lent
--   run.lua       what is kept between runs, and what a run carries; a run kept at a door
--   resume.lua    taking up a kept run, when the game is switched on (then let go)
--   title.lua     the title: the theatre, and three save slots (then let go)
--   lines.lua     every word, in Tamil and English
--   fx.lua        scraps, sparks, and the drops of ink (mai)
--   ending.lua    the two endings, as scenes (then let go)
--   pages.lua     the pages of the King's story (read when wanted)
--   sound.lua     the sound effects by name; the music is rooms.lua's
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
local sound   = require("sound")

local cam = { x = 0, y = 0 }
local show = false
local mode = "title"                    -- "title", "play", "pause", "card", "ask" (take up a kept run?), or "scene"
local asking                            -- resume.lua, while it asks
local titling                           -- title.lua, while the title shows
local playing, after_scene              -- ending.lua, while an ending plays; what follows it
local card, card2, card_t, card_then = nil, nil, 0, nil
local toast, toast_t = nil, 0
local hint, hint2, hint_for = nil, nil, nil
local CARD = 150                        -- frames a card shows (A skips after a second)

local to_title                          -- (below: the title)

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
  preload(rooms.ACTORS)
  to_title()
end

-- The title: three save slots. A slot chosen, its save is read, and Komali
-- is in the Courtyard; a run kept at a door in that slot may be taken up.
local function play_slot(n)
  titling = nil
  unrequire("title")
  run.load(n)
  home()
  mode = "play"
  if run.kept() then mode, asking = "ask", require("resume") end
end

to_title = function()
  titling = require("title")
  if titling.skip then play_slot(titling.skip) return end
  titling.open()
  mode = "title"
end

local function show_card(a, b, after, c, frames)
  -- broken into lines that fit: the first line large, the rest small
  font()
  a = table.concat(text.wrap(a, 34), "\n")
  font("small")
  b = b and table.concat(text.wrap(b, 36), "\n")
  if c then b = (b and b .. "\n" or "") .. c end
  font()
  mode, card, card2, card_t, card_then = "card", a, b, frames or CARD, after
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

-- the run played through: a card, then back to the Aasaan's box
local freeing = false                   -- waiting for the player to choose who goes free
local function finish(said, said2)
  run.drop()
  if not run.typed then run.data.played = run.data.played + 1 run.keep() end
  show_card(said, run.typed and lines.t("seeded") or said2, home, summary())
end

local function title(r) return lines.role(r:sub(1, 1):upper() .. r:sub(2)) end

-- an ending, played as a scene (ending.lua), in the Courtyard: the palace
-- and its code are let go first. Then the card (said, said2: read before
-- the palace's words go).
local function play_scene(which, said, said2)
  rooms.enter("map.ooru", nil, body)
  playing, after_scene = require("ending"), function() finish(said, said2) end
  playing.open(which)
  mode = "scene"
end

-- The Puppet King beaten in an act: the curtain falls, and the door on
-- opens. After the third he lets one puppet go, chosen by the player; with
-- all six home, he comes home himself. In hard mode it is his shadow, and
-- tearing it in the third act is Ending B.
local function king_beaten(b)
  if b.act < 3 then say(lines.t("curtain")) return end
  run.cleared = run.cleared + 1
  run.add_oil(b.oil or 25)
  if b.shade then                       -- hard: the King's shadow torn, Ending B
    if run.typed then finish(lines.t("done")) return end
    run.data.ending_b = true
    run.keep()
    play_scene("b", lines.t("the_end"))
    return
  end
  local left = 0
  for _, r in ipairs(require("pick").PUPPETS) do if not run.saved(r) then left = left + 1 end end
  if run.typed then finish(lines.t("done"))
  elseif left == 0 then
    run.free("king")
    play_scene("a", lines.t("king_home"), lines.t("hard_now"))
  else rooms.want("pick").open("free") freeing = true end
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
  if mode == "scene" then
    if playing.update(i) then
      playing = nil
      unrequire("ending")
      mode = "play"
      after_scene()
    end
    return
  end
  if mode == "title" then
    local n = titling.update(i, select_p)
    if n then play_slot(n) end
    return
  end
  if mode == "ask" then                 -- a kept run: taken up, or let go
    if asking.update(i, body) then
      asking = nil
      unrequire("resume")
      cam.x, cam.y = body.k.x + 5 - 160, body.k.y + 10 - 140
      mode = "play"
    end
    return
  end
  if mode == "pause" then
    if i.pause then mode = "play" music_pause(false) end
    if select_p then run.set_language(lines.lang == "ta" and "en" or "ta") end
    if i.attack then                    -- back to the title (the run stays kept at its last door)
      music_pause(false)
      run.keep()
      save_commit()
      to_title()
    end
    return
  end
  local shop, pk = rooms.shop, rooms.pick
  if shop and shop.update(i, body) then return end
  if pk and pk ~= shop and pk.update(i, body) then return end
  if freeing then                       -- chosen: that puppet goes home, and so does Komali
    freeing = false
    run.free(rooms.pick.freed)
    finish(lines.t("freed", title(rooms.pick.freed)))
    return
  end
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

  if i.pause then mode = "pause" music_pause(true) return end
  run.time = run.time + 1
  if rooms.update(i, body) then          -- through a door: the world waits
    if rooms.started then                -- into the first story: the run begins
      rooms.started = false
      run.start(body, rooms.MIDDLE, rooms.LAST)
      if run.typed then say(lines.t("seeded")) end
    end
    if rooms.came then                   -- through a door in a run: keep it here
      rooms.came = false
      if run.seed then run.keep_at(body, rooms.name, rooms.from) end
      local b = shadows.boss
      if b and b.shade then say(lines.t("shade_in", title(b.role))) end
    end
    if rooms.ended then
      rooms.ended = false
      run.drop()
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
  if body.k.health < before then fight.hit(false, true) end   -- struck: the world stops too (body.lua says ow)
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
  local got = fx.update(body.k)
  if got > 0 then fight.mai = fight.mai + got sound.play("mai") end
  follow()
  -- a page of the King's story: picked up, and read
  local px = rooms.page_x
  if px and math.abs(body.k.x + body.k.w / 2 - px) < 10 and math.abs(body.k.y + body.k.h - rooms.page_y) < 20 then
    rooms.page_x = nil
    local n, pages = run.find_page(rooms.def().story), require("pages")
    sound.play("page")
    show_card(lines.t("page_n", n, pages.COUNT), pages.text(n), nil, nil, 900)    -- (time to read it)
    unrequire("pages")
    return
  end
  -- the boss torn: his role lent, and oil
  local b = shadows.boss
  if shadows.beaten and b and b.act then
    shadows.beaten = false
    king_beaten(b)
  elseif shadows.beaten and b and b.shade then   -- a shadow boss: torn, and it lends nothing
    shadows.beaten = false
    run.cleared = run.cleared + 1
    run.add_oil(b.oil)
    sound.play("oil")
    say(lines.t("shade_torn") .. "   " .. lines.t("oil", b.oil))
  elseif shadows.beaten and b then
    shadows.beaten = false
    run.cleared = run.cleared + 1
    -- both places full: which role to give up for his, if any
    local full = #fight.carried >= 3
    for _, r in ipairs(fight.carried) do if r.name:lower() == b.role then full = false end end
    run.lent[b.role] = true
    if full then rooms.want("pick").open("lend", b.role) else fight.lend(b.role) end
    run.add_oil(b.oil)
    sound.play("oil")
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
    run.drop()
    rooms.music_stop(1500)
    sound.play("fallen")
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
    if run.hard() then print(lines.t("hard"), 276 - text.width(lines.t("hard")), 40, C.vermil) end
    local y = 64
    local names = ""
    for n, r in ipairs(fight.carried) do names = names .. (n > 1 and ", " or "") .. lines.role(r.name) end
    print(lines.t("roles") .. ": " .. names, 44, y, C.cloth)
    y = y + 20
    local cs = ""
    for n, c in ipairs(run.charms) do cs = cs .. (n > 1 and ", " or "") .. lines.t(c) end
    print(lines.t("charms") .. ": " .. (cs == "" and "-" or cs), 44, y, C.cloth)
    y = y + 20
    print(lines.t("mai") .. ": " .. fight.mai .. "    " .. lines.t("oil_k") .. ": " .. run.data.oil
          .. "    " .. lines.t("pages_k") .. ": " .. #run.data.pages, 44, y, C.cloth)
    if run.seed then
      y = y + 20
      print(summary(), 44, y, C.cloth)
      if run.typed then print(lines.t("seeded"), 44, y + 16, C.vermil) end
    end
    text.center(lines.t("resume", buttons.start, buttons.select), 182, C.tan)
    text.center(lines.t("to_title", buttons.b), 196, C.tan)
  end
  if mode == "ask" then asking.draw(say_at) end
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
  if mode == "title" then titling.draw() return end
  if mode == "scene" then playing.draw() return end
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
  body.draw(role.colours, pose and body.FRAME[pose], role.frames, role.moves, role.sheet)
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
