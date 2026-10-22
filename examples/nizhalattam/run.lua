-- run.lua — what is kept between runs, and what a run carries.
--
--   run.load()            once, at the start
--   run.data              kept: oil, runs played through, the language, the
--                         repairs, the puppets saved, the roles chosen
--   run.begin(body)       back at the Aasaan's box: the next run not begun
--   run.start(body, middle)  a run begins (through the booth's screen): its
--                         seed, the order of its stories, its roles
--   run.lent[name]        the roles lent in this run (they need no place bought)
--   run.charm(name)       does Komali carry this charm?
--   run.add_oil(n)        oil, kept at once (not in a seeded run)
--   run.clock()           the run's time, as m:ss
--
-- A run carries mai, charms and roles lent; all of it is lost when the run
-- ends, by falling or by playing the stories through. Oil and the rest of
-- run.data are kept in the save.
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
local KEY, VERSION = "progress", 1
run.SEEDS = 100000                      -- seeds are five digits

local function defaults()
  return { version = VERSION, lang = "ta", oil = 0, played = 0, falls = 0, runs = 0,
           repairs = {},                  -- the Aasaan's repairs: r_health, r_double, r_mai
           saved = {},                    -- the puppets brought home, by role name
           chosen = {},                   -- the saved puppets' roles carried from the start
           king = false }                 -- the Puppet King come home (all six saved, then him)
end

function run.load()
  local d = load(KEY)
  if type(d) ~= "table" or d.version ~= VERSION then
    local fresh = defaults()
    if type(d) == "table" and (d.lang == "en" or d.lang == "ta") then fresh.lang = d.lang end
    d = fresh
  end
  for k, v in pairs(defaults()) do if d[k] == nil then d[k] = v end end
  run.data = d
  lines.use(d.lang)
end

function run.keep() save(KEY, run.data) end

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
