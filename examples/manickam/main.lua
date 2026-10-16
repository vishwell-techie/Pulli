-- Manickam (மாணிக்கம், "ruby"): Pulli's showcase, and its test of the hardware.
--
-- Kayal, the lamp-keeper's granddaughter, sets out with Minmini the firefly
-- to gather the seven pieces of the temple's ruby before Karthigai Deepam.
-- She is no fighter: she dodges, and uses light.
--
-- The game is split over several files, each loaded with require():
--   core.lua       scenes, buttons, fades and text: the game's own small
--                  versions of four SDK helpers, as Lua memory is tight
--   story.lua      every word shown; the words are in lines_ta.lua and lines_en.lua
--   progress.lua   settings and progress, kept as one table in the save data
--   title.lua      the title screen, chapter select and options
--   play.lua       the chapters in order, the top bar, pause, Paati's stories
--   world.lua      what every region shares: Kayal, Minmini, slimes, lamps...
--   opening.lua, ch0.lua ... ch6.lua   the opening and the chapters
--   script.lua     cut-scenes, written as functions that read in order
--   talk.lua       the box people talk in
--   irul.lua       the shadow serpent
--   dark.lua       night, and the lights in it
--   fx.lua         sparks, dust and fireworks
--   bench.lua      the benchmark: SELECT on the title screen switches it on
-- The SDK helper move comes from the SDK's sdk/ folder; packing the game
-- puts it in.
--
-- sprites.png is a full 512x256 sheet, the most the console holds: the title
-- art fills its top-left 320x240, and every sprite and tile fits around it.
-- The maps are drawn in Tiled and share one tileset, sprites.tsx, which
-- holds each tile's flags: solid, water, thorns, deep water, dark, lamp,
-- mirror and beam.

local core     = require("core")
local progress = require("progress")
require("play")
require("title")

function init()
  progress.load()
  core.go("title")
end

function update(dt) core.update(dt) end
function draw() core.draw() end
