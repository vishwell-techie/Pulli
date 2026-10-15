-- Manickam (மாணிக்கம், "ruby"): Pulli's showcase, and its test of the hardware.
--
-- Kayal, the lamp-keeper's granddaughter, sets out with Minmini the firefly
-- to gather the seven pieces of the temple's ruby before Karthigai Deepam.
-- She is no fighter: she dodges, and uses light.
--
-- The game is split over several files, each loaded with require():
--   story.lua      every word shown, in Tamil and English
--   progress.lua   settings and progress, kept as one table in the save data
--   title.lua      the title screen, chapter select and options
--   level.lua      the gem hunt, the first chapter so far
--   bench.lua      the benchmark: SELECT on the title screen switches it on
-- The helpers they use (scene, menu, dialog and the rest) come from the
-- SDK's sdk/ folder; packing the game puts them in.
--
-- sprites.png is a full 512x256 sheet, the most the console holds: the title
-- art fills its top-left 320x240, and every sprite and tile fits around it.

local scene      = require("scene")
local input      = require("input")
local transition = require("transition")
local progress   = require("progress")
require("level")
require("title")
require("bench")

function init()
  progress.load()
  scene.go("title")
end

function update(dt)
  input.update(dt)
  transition.update(dt)
  scene.update(dt)
end

function draw()
  scene.draw()
  transition.draw()
end
