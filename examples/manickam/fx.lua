-- fx.lua — sparks, dust, splashes and fireworks: a fixed number of dots
-- kept in plain arrays of numbers.
--
--   local fx = require("fx")
--   fx.burst(x, y, 20, fx.SPARK)          -- twenty sparks from (x, y)
--   fx.burst(x, y, 1, fx.RUBY, 0, -10)    -- one dot, with its own velocity
--   fx.update(dt)  fx.draw()              -- with the world, before camera()
--
-- The SDK's particles helper keeps a table for each dot. On a 64-bit
-- desktop a table costs about half a kilobyte, which this game, with
-- hundreds of dots in its biggest scenes, cannot spare: here each dot is
-- one slot in five arrays, and a burnt-out dot gives its slot to the last
-- one alive. A dot's style and age share one number: the style's place in
-- fx.STYLES, plus how far through its life it is, from 0 up to 1.
--
-- The arrays grow to the most dots alive at once and stay that size;
-- fx.release() lets their memory go after a big scene.

local fx = { MAX = 64, n = 0 }
local px, py, vx, vy, age = {}, {}, {}, {}, {}

-- Styles: speed, how much it varies, gravity, life in seconds, colours from
-- young to old. A region may add its own to the end.
fx.STYLES = {
  { speed = 50, vary = 0.6, gravity = 40, life = 0.7, colors = { 10, 9, 8, 2 } },      -- spark
  { speed = 25, vary = 0.8, gravity = -10, life = 0.5, colors = { 6, 13, 5 } },        -- dust
  { speed = 35, vary = 0.5, gravity = 120, life = 0.5, colors = { 7, 12, 28 } },       -- splash
  { speed = 12, vary = 1, gravity = -8, life = 1.2, colors = { 10, 23, 9, 41 } },      -- glow
  { speed = 30, vary = 0.7, gravity = -20, life = 0.8, colors = { 2, 50, 34 } },       -- dark
  { speed = 20, vary = 0.5, gravity = 0, life = 0.4, colors = { 7, 14, 8, 24 } },      -- ruby
}
fx.SPARK, fx.DUST, fx.SPLASH, fx.GLOW, fx.DARK, fx.RUBY = 1, 2, 3, 4, 5, 6

function fx.clear() fx.n = 0 end

-- Allow up to `most` dots, and make their slots now, so a burst in the
-- middle of a scene never makes the arrays grow.
function fx.reserve(most)
  fx.MAX = most
  for i = #px + 1, most do px[i], py[i], vx[i], vy[i], age[i] = 0, 0, 0, 0, 1 end
end

-- Back to the usual 64, letting the memory of a bigger scene go.
function fx.release()
  fx.n, fx.MAX = 0, 64
  px, py, vx, vy, age = {}, {}, {}, {}, {}
end

function fx.burst(x, y, n, s, dx, dy)
  local st = fx.STYLES[s]
  for _ = 1, n do
    if fx.n >= fx.MAX then return end
    local i = fx.n + 1
    fx.n = i
    local a, v = math.random() * 6.2832, st.speed * (1 - st.vary * math.random())
    px[i], py[i], age[i] = x, y, s + (dx and 0 or 0.4 * math.random())
    vx[i], vy[i] = dx or math.cos(a) * v, dy or math.sin(a) * v
  end
end

function fx.update(dt)
  local i, styles = 1, fx.STYLES
  while i <= fx.n do
    local st = styles[age[i] // 1]
    local a = age[i] + dt / st.life
    if a // 1 ~= age[i] // 1 then              -- burnt out
      local j = fx.n
      px[i], py[i], vx[i], vy[i], age[i] = px[j], py[j], vx[j], vy[j], age[j]
      fx.n = j - 1
    else
      age[i] = a
      vy[i] = vy[i] + st.gravity * dt
      px[i], py[i] = px[i] + vx[i] * dt, py[i] + vy[i] * dt
      i = i + 1
    end
  end
end

function fx.draw()
  local styles = fx.STYLES
  for i = 1, fx.n do
    local c = styles[age[i] // 1].colors
    pset(px[i], py[i], c[age[i] % 1 * #c // 1 + 1])
  end
end

return fx
