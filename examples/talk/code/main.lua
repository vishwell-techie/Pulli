-- Talk: the SDK helpers in one small scene.
--
--   dialog.lua          the villager speaks and asks a question
--   inventory.lua       the bag the gems go into, kept in the save data
--   quest.lua           "fill your bag", counted gem by gem and saved
--   tween.lua           the gem flies from the villager to the bag
--   particles.lua       sparks where the gem lands
--   camera_follow.lua   the view follows the player along a wide field
--   input.lua           a press of A counts once, however long it is held
--   anim.lua            the player's steps and the villager's idling
--   text.lua            the quest, set against the right-hand edge
--
-- The helpers are ordinary Lua files in the SDK's sdk/ folder. Requiring
-- one is all it takes: packing the game puts it in. To change one, copy it
-- into this folder and the game uses your copy:
--   python3 tools/pulli.py add examples/talk dialog
--
-- Walk to the villager with left and right and press A to talk.

local dialog    = require("dialog")
local inventory = require("inventory")
local tween     = require("tween")
local follow    = require("camera_follow")
local quest     = require("quest")
local particles = require("particles")
local input     = require("input")
local anim      = require("anim")
local text      = require("text")

local W, H = 320, 240
local FIELD = 640               -- the field is two screens wide
local GROUND = 110              -- the y everyone stands at
local GEM, PLAYER, VILLAGER, TREE = 6, 8, 10, 5

local player = { x = 60, flip = false }
local walker = anim.new({
  stand = { frames = { PLAYER } },
  walk  = { frames = { PLAYER, PLAYER + 1 }, fps = 8 },
})
local idler = anim.new({ idle = { frames = { VILLAGER, VILLAGER + 1 }, fps = 3 } })
local villager = { x = 420 }
local bag = inventory.new(4, 3) -- 4 kinds of thing, at most 3 of each
local cam = follow.new({ smooth = 6, dead_w = 60 })
local gem = { x = 0, y = 0, flying = false }
local sparks = particles.new(40)
local SPARK = { speed = 50, life = 0.5, gravity = 140, colors = { 7, 10, 9 } }   -- made once, reused
local bag_text, quest_text = "", ""

-- Text for the top of the screen, built only when something changes.
local function show_bag()
  bag_text = "BAG: " .. bag:count("gem") .. " GEM" .. (bag:count("gem") == 1 and "" or "S")
  local _, _, have, need = quest.step("bag")
  if quest.state("bag") == "active" then
    quest_text = "QUEST: " .. have .. " OF " .. need
  else
    quest_text = quest.state("bag") == "done" and "QUEST DONE" or ""
  end
end

-- The gem leaves the villager and lands in its place in the bag, at the top
-- of the screen. It flies across the screen, not the field, so its place is
-- worked out from where the camera is looking.
local function give_gem()
  gem.x, gem.y, gem.flying = villager.x - cam.x, GROUND - 12, true
  local place = 100 + (bag:count("gem") + 1) * 10
  tween.to(gem, { x = place, y = 2 }, 0.7, "out_back", function()
    gem.flying = false
    bag:add("gem")
    quest.advance("bag")        -- one gem nearer; the third finishes the quest
    bag:save("bag")
    quest.save("quest")
    show_bag()
    sparks:emit(place + 4, 6, 14, SPARK)
    cam:shake(3, 0.25)
    if quest.state("bag") == "done" then
      dialog.say("Villager", "A full bag! You have done all I hoped for.")
    end
  end)
end

local function talk()
  if bag:count("gem") >= 3 then
    dialog.say("Villager", "Your bag is full. Three gems is plenty for one traveller.")
    return
  end
  if quest.start("bag") then    -- true only the first time
    dialog.say("Villager", "Traveller! Fill your bag with three gems and you will be ready for the road.")
  end
  dialog.ask("Villager", "I found this gem by the river. Would you like to have it?",
    { "Yes, please", "No, keep it" },
    function(choice)
      if choice == 1 then
        dialog.say("Villager", "Here you are. Look after it!", give_gem)
      else
        dialog.say("Villager", "As you wish. Come back if you change your mind.")
      end
    end)
end

function init()
  quest.define("bag", "A Full Bag", { { "Collect three gems", need = 3 } })
  quest.load("quest")           -- how far it had got last time
  bag:load("bag")               -- whatever was carried last time
  show_bag()
  cam:bounds(0, 0, FIELD, H)
  cam:snap(player.x, GROUND)
end

function update(dt)
  input.update(dt)
  tween.update(dt)
  sparks:update(dt)
  idler:update(dt)
  cam:update(player.x + 4, GROUND, dt)

  -- While someone is talking, or a gem is in the air, the player waits.
  if dialog.update(dt) or gem.flying then return end

  local dx = 0
  if btn("left")  then dx = -1; player.flip = true end
  if btn("right") then dx = 1; player.flip = false end
  player.x = math.max(8, math.min(FIELD - 16, player.x + dx * 70 * dt))
  walker:play(dx ~= 0 and "walk" or "stand")
  walker:update(dt)

  if input.pressed("a") and math.abs(player.x - villager.x) < 20 then talk() end
end

function draw()
  cls(12)                       -- sky
  cam:apply()                   -- the world, moved by the camera
  rectfill(0, GROUND + 8, FIELD, H, 27)
  for x = 20, FIELD, 70 do spr(TREE, x, GROUND) end
  idler:draw(villager.x, GROUND)
  walker:draw(player.x, GROUND, player.flip)
  if math.abs(player.x - villager.x) < 20 and not dialog.active() and not gem.flying then
    print("A", villager.x, GROUND - 14, 7)
  end

  camera()                      -- the screen: the bag and the talking
  rectfill(0, 0, W, 11, 32)
  for i = 1, bag:count("gem") do spr(GEM, 100 + i * 10, 2) end
  print(bag_text, 4, 2, 7)
  text.right(quest_text, 316, 2, 10)
  if gem.flying then spr(GEM, gem.x, gem.y) end
  sparks:draw()
  dialog.draw()
end
