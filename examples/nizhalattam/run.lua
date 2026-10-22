-- run.lua — what is kept between runs, and what a run carries.
--
--   run.load(slot)        a save slot (1 to 3), chosen at the title
--   run.read(slot)        a slot's save as it is written, or nil if empty
--   run.language()        the language chosen, for every slot;
--   run.set_language(l)   and changing it
--   run.data              kept: oil, runs played through, the language, the
--                         repairs, the puppets saved, the roles chosen
--   run.begin(body)       back at the Aasaan's box: the next run not begun
--   run.start(body, middle)  a run begins (through the booth's screen): its
--                         seed, the order of its stories, its roles
--   run.lent[name]        the roles lent in this run (they need no place bought)
--   run.charm(name)       does Komali carry this charm?
--   run.add_oil(n)        oil, kept at once (not in a seeded run)
--   run.hard()            hard mode: once the Puppet King is home, for good
--   run.clock()           the run's time, as m:ss
--
-- A run carries mai, charms and roles lent; all of it is lost when the run
-- ends, by falling or by playing the stories through. Oil and the rest of
-- run.data are kept in the save.
--
-- A run in progress is kept at every door (run.keep_at): where Komali is,
-- and everything the run carries. The console can be switched off, and the
-- run taken up again where it was kept (resume.lua). Ending the run, by
-- falling or by playing it through, lets it go (run.drop).
--
--   run.keep_at(body, room, from)   at a door: keep the run
--   run.kept()                      the run kept, if any
--   run.drop()                      the run is over: keep it no more
--
-- Each run has a seed, shown in the pause and at the end. It decides the
-- order of the stories between the Screen (always first) and the Lamp
-- Palace (always last). A fresh seed comes from the moment Komali steps
-- into the Screen; a seed typed at the Aasaan's box plays that run again,
-- but keeps nothing: no oil, no puppet saved, nothing counted.

local lines = require("lines")
local fight = require("fight")

local run = { charms = {}, sharp = {}, seed = nil, typed = false, next_seed = nil, lent = {},
              order = { "screen" }, half = 0, torn = false, cleared = 0, time = 0 }
local SLOT, OLD, VERSION = "slot", "progress", 1   -- (the one save from before there were slots: slot 1)
run.SLOT, run.OLD = SLOT, OLD
run.SEEDS = 100000                      -- seeds are five digits

local function defaults()
  return { version = VERSION, lang = "ta", oil = 0, played = 0, falls = 0, runs = 0,
           repairs = {},                  -- the Aasaan's repairs: r_health, r_double, r_mai
           saved = {},                    -- the puppets brought home, by role name
           chosen = {},                   -- the saved puppets' roles carried from the start
           king = false,                  -- the Puppet King come home (all six saved, then him)
           ending_b = false,              -- his shadow torn, in hard mode
           kept = false }                 -- the run in progress, kept at its last door
end

-- a slot's save, as it was written (slot 1 may still be the old save)
function run.read(slot)
  local d = load(SLOT .. slot)
  if slot == 1 and type(d) ~= "table" then d = load(OLD) end
  if type(d) ~= "table" or d.version ~= VERSION then return nil end
  return d
end

function run.load(slot)
  run.slot = slot
  local d = run.read(slot) or defaults()
  for k, v in pairs(defaults()) do if d[k] == nil then d[k] = v end end
  run.data = d
  if slot == 1 and load(OLD) then run.keep() save(OLD, nil) end      -- the old save moves into slot 1
  lines.use(run.language())
end

function run.keep() save(SLOT .. run.slot, run.data) end

-- the language is the console's, not a slot's (the old save said it)
function run.language()
  local l = load("lang")
  if l ~= "en" and l ~= "ta" then
    local old = load(OLD)
    l = type(old) == "table" and (old.lang == "en" or old.lang == "ta") and old.lang or "ta"
  end
  return l
end

function run.set_language(l)
  lines.use(l)
  save("lang", l)
end

function run.hard() return run.data.king == true end

function run.saved(name)
  for _, s in ipairs(run.data.saved) do if s == name then return true end end
  return false
end

-- Back at the box, with the repairs bought so far: health, the double
-- jump, mai. Komali wears his own role until the run begins.
function run.begin(body)
  local r = run.data.repairs
  fight.mai = 50 * (r.r_mai or 0)
  if body then
    body.k.max = 100 + 15 * (r.r_health or 0)
    body.k.double = (r.r_double or 0) > 0
  end
  for n = #run.charms, 1, -1 do run.charms[n] = nil end
  for k in pairs(run.sharp) do run.sharp[k] = nil end
  fight.wear({ "komali" })
  fight.sharp, fight.charms = run.sharp, run.charms
  run.seed, run.typed, run.order, run.half, run.torn = nil, false, { "screen" }, 0, false
  run.cleared, run.time = 0, 0
  for k in pairs(run.lent) do run.lent[k] = nil end
  if body then body.k.ward = 0 end
end

-- The run's own random numbers, from its seed (math.random is the
-- effects'): the same seed, the same run.
local state = 1
local function rand(n)                  -- xorshift, on 32-bit integers
  state = state ~ (state << 13)
  state = state ~ (state >> 17)
  state = state ~ (state << 5)
  return (state & 0x7fffffff) % n + 1
end

-- A run begins: its seed (typed at the box, or from this moment), the
-- order of the stories between the first and the last, where the halfway
-- tear falls, and the roles chosen at the box (as many as places bought).
function run.start(body, middle, last)
  if run.next_seed then run.seed, run.typed, run.next_seed = run.next_seed, true, nil
  else run.seed, run.typed = (stat("frame") * 7919 + run.data.runs * 104729) % run.SEEDS, false end
  if not run.typed then run.data.runs = run.data.runs + 1 run.keep() end
  state = (run.seed + 1) * 0x9e3779b1 | 1           -- spread the seed's bits, then stir
  for _ = 1, 4 do rand(2) end
  local order = { "screen" }
  for _, s in ipairs(middle) do table.insert(order, rand(#order) + 1, s) end
  if last then order[#order + 1] = last end
  run.order, run.half, run.torn, run.cleared, run.time = order, #order // 2, false, 0, 0
  for k in pairs(run.lent) do run.lent[k] = nil end
  local wear, places = { "komali" }, run.data.repairs.r_slot or 0
  for _, r in ipairs(run.data.chosen) do
    if run.saved(r) and #wear <= places then wear[#wear + 1] = r end
  end
  fight.wear(wear)
end

-- A puppet the Puppet King lets go: saved, from the next run on (not in a
-- run from a typed seed). With all six saved, the King himself comes home.
function run.free(name)
  if run.typed then return end
  if name == "king" then run.data.king = true
  elseif not run.saved(name) then run.data.saved[#run.data.saved + 1] = name end
  run.keep()
end

-- the names of a set (lent, sharp), as a list, and back
local function list(set) local l = {} for k, v in pairs(set) do if v then l[#l + 1] = k end end return l end
local function copy(l) local c = {} for n, v in ipairs(l) do c[n] = v end return c end
run.copy = copy

function run.keep_at(body, room, from)
  local roles = {}
  for n, r in ipairs(fight.carried) do roles[n] = r.name:lower() end
  run.data.kept = {
    seed = run.seed, typed = run.typed, order = copy(run.order), half = run.half, torn = run.torn,
    cleared = run.cleared, time = run.time, room = room, from = from,
    health = body.k.health, mai = fight.mai, charms = copy(run.charms), sharp = list(run.sharp),
    roles = roles, worn = fight.worn, lent = list(run.lent),
  }
  run.keep()
  save_commit()                          -- a door is a checkpoint: written now, not at the next interval
end

function run.kept() return run.data.kept or nil end

function run.drop()
  if run.data.kept then run.data.kept = false run.keep() save_commit() end
end

function run.charm(name)
  for _, c in ipairs(run.charms) do if c == name then return true end end
  return false
end

function run.add_oil(n)
  if run.typed then return end            -- a seeded run keeps nothing
  run.data.oil = run.data.oil + n
  run.keep()
end

function run.clock()
  local s = run.time // 60
  return string.format("%d:%02d", s // 60, s % 60)
end

return run
