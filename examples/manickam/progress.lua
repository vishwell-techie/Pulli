-- progress.lua — what the game remembers between plays: how far Kayal has
-- got, and the player's settings, kept as one table in the save data.
--
--   local progress = require("progress")
--   progress.load()                  -- once, at the start
--   progress.data.unlocked = 1
--   progress.save()                  -- kept; written in the background
--   progress.checkpoint()            -- kept and written now
--
-- The manifest asks for save_mode = "auto", so a change is written within a
-- minute even if the game never reaches a checkpoint.

local story = require("story")

local progress = {}
local KEY, VERSION = "progress", 1

local function defaults()
  return {
    version = VERSION,
    lang = "ta", music = true, sfx = true,   -- settings
    started = false,                         -- a game has been begun
    chapter = 0, unlocked = 0,               -- where Kayal is, and how far she has been
    best = {},                               -- best time per chapter, in seconds
  }
end

-- Settings and progress from the save data, or the defaults the first time.
-- A save from a later version is ignored rather than misread.
function progress.load()
  local d = load(KEY)
  if type(d) ~= "table" or d.version ~= VERSION then d = defaults() end
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

-- A new game keeps the settings and forgets the rest.
function progress.reset()
  local d, keep = defaults(), progress.data
  d.lang, d.music, d.sfx = keep.lang, keep.music, keep.sfx
  progress.data = d
  progress.save()
end

-- Sounds and music go through these, so the settings are obeyed everywhere.
function progress.sfx(n)
  if progress.data.sfx then sfx(n) end
end

function progress.music(n, fade)
  if progress.data.music then music(n, fade) end
end

return progress
