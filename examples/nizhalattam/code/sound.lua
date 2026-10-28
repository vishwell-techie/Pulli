-- sound.lua — the sound effects by name (sfx/, made by the sound script,
-- private). sound.play("jump") plays one on a free channel.

local N = {
  jump = 0,
  land = 1,
  slap = 2,
  hit = 3,
  heavy = 4,
  blocked = 5,
  torn = 6,
  hurt = 7,
  dodge = 8,
  mai = 9,
  oil = 10,
  door = 11,
  select = 12,
  buy = 13,
  no = 14,
  page = 15,
  warn = 16,
  arrow = 17,
  fire = 18,
  pound = 19,
  summon = 20,
  skill = 21,
  swap = 22,
  fall = 23,
  fallen = 24,
  shield = 25,
}

local sound = { N = N }

function sound.play(name) sfx(N[name]) end

return sound
