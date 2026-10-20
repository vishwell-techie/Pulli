-- run.lua — what is kept between runs, and what a run carries.
--
--   run.load()            once, at the start
--   run.data              kept: oil, the Screen played, the language
--   run.begin()           a new run, at the Aasaan's box
--   run.charm(name)       does Komali carry this charm?
--   run.add_oil(n)        oil, kept at once
--
-- A run carries mai, charms and roles lent; all of it is lost when the run
-- ends, by falling or by playing the story through. Oil and the rest of
-- run.data are kept in the save.

local lines = require("lines")
local fight = require("fight")

local run = { charms = {}, sharp = {} }
local KEY, VERSION = "progress", 1

local function defaults()
  return { version = VERSION, lang = "ta", oil = 0, screen_played = 0, falls = 0,
           repairs = {} }                  -- the Aasaan's repairs: r_health, r_double, r_mai
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

-- A new run, with the repairs bought so far: health, the double jump, mai.
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
end

function run.charm(name)
  for _, c in ipairs(run.charms) do if c == name then return true end end
  return false
end

function run.add_oil(n)
  run.data.oil = run.data.oil + n
  run.keep()
end

return run
