-- role_veeran.lua — the warrior's role, as Komali wears it (fight.lua reads
-- it when he first carries it): a three-hit sword combo, a heavy slash
-- gathered with B held, the shield bash, an overhead slash coming in; he
-- takes 15% less from every blow. Blows as in fight.lua: frames before (s),
-- landing (a), after (r); cost (n); the box struck (w x h).

local C = require("colours")

return {
  name = "Veeran",
  colours = { C.red, C.blue, C.vermil, C.sky, C.red + 32, C.blue + 32,       -- blue tunic,
              C.saffron, C.cloth, C.saffron + 32, C.cloth + 32,          -- a white veshti,
              C.marigold, C.silver, C.marigold + 32, C.silver + 32 },    -- a steel helmet
  frames = 256,                                    -- Komali's frames with a sword in hand
  combo = { { s = 5, a = 4, r = 10, n = 12, w = 20, h = 16 },
            { s = 5, a = 4, r = 10, n = 12, w = 20, h = 16 },
            { s = 7, a = 5, r = 14, n = 20, w = 22, h = 18 } },
  air = { s = 4, a = 5, r = 8, n = 12, w = 18, h = 22 },
  heavy = { s = 2, a = 6, r = 16, n = 40, w = 26, h = 20, heavy = true },
  swap = { s = 2, a = 6, r = 8, n = 18, w = 22, h = 24, heavy = true },
  skill = "bash", wait = 300,
  slow = 0.3, dodge_wait = 1, guard = 0.15,        -- takes 15% less from every blow
}
