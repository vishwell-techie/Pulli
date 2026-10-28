-- progress.lua — what the game remembers between plays, kept as one table in
-- the save data, and the numbers of its sounds and music.
--
--   local progress = require("progress")
--   progress.load()                  -- once, at the start
--   progress.data.unlocked = 1
--   progress.save()                  -- kept; written in the background
--   progress.checkpoint()            -- kept and written now
--   progress.sfx(7)                  -- the lamp sound, if sounds are on
--
-- The manifest asks for save_mode = "auto", so a change is written within a
-- minute even if the game never reaches a checkpoint.

local story = require("story")

local progress = {}
local KEY, VERSION = "progress", 2

-- Sounds and music are played by number: sfx/ and music/ are numbered in
-- order of file name. Every call says which in a comment.
--   sfx    0 pickup  1 hurt  2 piece  3 lost  4 pause  5 resume  6 flare
--          7 lamp  8 door  9 key  10 switch  11 stone  12 splash  13 fall
--          14 crash  15 mirror  16 blip  17 move  18 choose  19 shatter
--          20 wind  21 hiss  22 orb  23 launch  24 boom  25 heart  26 chime
--          27 rumble  28 frog  29 cricket
--   music  0 title  1 village  2 fields  3 forest  4 lake  5 hills
--          6 temple  7 irul  8 festival  9 shadow

local function defaults()
  return {
    version = VERSION,
    lang = "ta", music = true, sfx = true,   -- settings
    started = false,                         -- a game has been begun
    chapter = 0, unlocked = 0,               -- where Kayal is, and how far she has been
    pieces = 0,                              -- the ruby pieces found, one bit each
    hearts = 3,                              -- three, and one more for each heart lotus
    pots = 0, lamp = false,                  -- the potter's pots, and his gift
    lotuses = 0,                             -- lotuses for the festival
    got = {},                                -- things picked up, so they stay picked up
    seen = {},                               -- cut-scenes watched
  }
end

-- Settings and progress from the save data, or the defaults the first time.
-- A save from another version is not misread: its settings are kept and the
-- rest starts afresh.
function progress.load()
  local d = load(KEY)
  if type(d) ~= "table" then d = defaults() end
  if d.version ~= VERSION then
    local fresh = defaults()
    fresh.lang, fresh.music, fresh.sfx = d.lang or "ta", d.music ~= false, d.sfx ~= false
    d = fresh
  end
  for k, v in pairs(defaults()) do
    if d[k] == nil then d[k] = v end
  end
  progress.data = d
  story.lang = d.lang
  progress.bench = false                     -- the benchmark switch is never saved
end

function progress.save()
  save(KEY, progress.data)
end

function progress.checkpoint()
  progress.save()
  save_commit()
end

-- A new game keeps the settings and what has been seen, and forgets the rest.
function progress.reset()
  local d, keep = defaults(), progress.data
  d.lang, d.music, d.sfx, d.seen = keep.lang, keep.music, keep.sfx, keep.seen
  progress.data = d
  progress.save()
end

-- How many ruby pieces have been found.
function progress.piece_count()
  local n, bits = 0, progress.data.pieces
  while bits > 0 do n, bits = n + (bits & 1), bits >> 1 end
  return n
end

-- Sounds and music go through these, so the settings are obeyed everywhere.
-- progress.quiet is set while a cut-scene is being skipped.
function progress.sfx(n, channel)
  if progress.data.sfx and not progress.quiet then sfx(n, channel) end
end

function progress.music(n, fade)
  if progress.data.music then music(n, fade) else music_stop() end
end

return progress
