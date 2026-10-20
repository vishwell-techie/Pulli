-- fx.lua — what flies when blows land: paper scraps, sparks off a guard,
-- and the drops of ink (mai) a torn shadow leaves, which fly to Komali.
--
--   fx.tear(x, y, n)      a shadow torn: scraps, and n drops of mai
--   fx.spark(x, y)        a blow turned aside
--   fx.update(k)          once a frame; returns the mai picked up
--   fx.draw()
--
-- Everything is made once, here: nothing new is made while playing. The
-- bits are kept in a few long arrays rather than a table each (the SDK's
-- particles), which would cost half a kilobyte a bit.

local fx = {}

-- bits: scraps of paper and sparks
local BITS = 128
local bx, by, bvx, bvy, bt, bk = {}, {}, {}, {}, {}, {}
for n = 1, BITS do bx[n], by[n], bvx[n], bvy[n], bt[n], bk[n] = 0, 0, 0, 0, 0, 0 end
local alive = 0
local SCRAP, SPARK = 1, 2
local SCRAP_COL = { 15, 31, 22, 1 }
local SPARK_COL = { 7, 10, 9 }
local LIFE = { 54, 15 }

local function emit(x, y, count, kind, speed)
  for _ = 1, count do
    if alive >= BITS then return end
    alive = alive + 1
    local a = math.random() * 6.283
    local v = speed * (0.3 + math.random() * 0.7)
    bx[alive], by[alive], bt[alive], bk[alive] = x, y, LIFE[kind], kind
    bvx[alive], bvy[alive] = math.cos(a) * v, math.sin(a) * v - (kind == SCRAP and 1 or 0)
  end
end

-- drops of mai: where, how fast, and how long they have been out
local MAX = 40
local dx, dy, dvx, dvy, dt = {}, {}, {}, {}, {}
for n = 1, MAX do dx[n], dy[n], dvx[n], dvy[n], dt[n] = 0, 0, 0, 0, -1 end

function fx.tear(x, y, n)
  emit(x, y, 24, SCRAP, 1.4)
  for _ = 1, n do
    for d = 1, MAX do
      if dt[d] < 0 then
        dx[d], dy[d], dvx[d], dvy[d], dt[d] = x, y, (math.random() - 0.5) * 3, -1.5 - math.random() * 1.5, 0
        break
      end
    end
  end
end

function fx.spark(x, y) emit(x, y, 8, SPARK, 1.6) end

-- Drops arc out, then after a moment fly to Komali; returns how many he
-- caught this frame.
function fx.update(k)
  local n = 1
  while n <= alive do
    bt[n] = bt[n] - 1
    if bt[n] <= 0 then        -- done: the last one alive takes its place
      bx[n], by[n], bvx[n], bvy[n], bt[n], bk[n] =
        bx[alive], by[alive], bvx[alive], bvy[alive], bt[alive], bk[alive]
      alive = alive - 1
    else
      if bk[n] == SCRAP then   -- paper flutters down
        bvy[n] = math.min(bvy[n] + 0.04, 0.8)
        bvx[n] = bvx[n] * 0.96
      end
      bx[n], by[n] = bx[n] + bvx[n], by[n] + bvy[n]
      n = n + 1
    end
  end
  local got, cx, cy = 0, k.x + k.w / 2, k.y + k.h / 2
  for d = 1, MAX do
    local t = dt[d]
    if t >= 0 then
      t = t + 1
      dt[d] = t
      if t < 24 then
        dvy[d] = dvy[d] + 0.15
      else
        local ex, ey = cx - dx[d], cy - dy[d]
        local len = math.max(1, math.sqrt(ex * ex + ey * ey))
        local sp = math.min(6, 1 + (t - 24) * 0.25)
        dvx[d], dvy[d] = ex / len * sp, ey / len * sp
        if len < 8 then dt[d], got = -1, got + 1 end
      end
      dx[d], dy[d] = dx[d] + dvx[d], dy[d] + dvy[d]
    end
  end
  return got
end

function fx.draw()
  for n = 1, alive do
    local life = LIFE[bk[n]]
    if bk[n] == SCRAP then
      rectfill(bx[n], by[n], 2, 2, SCRAP_COL[1 + (life - bt[n]) * 4 // (life + 1)])
    else
      pset(bx[n], by[n], SPARK_COL[1 + (life - bt[n]) * 3 // (life + 1)])
    end
  end
  for d = 1, MAX do
    if dt[d] >= 0 then
      circfill(dx[d], dy[d], 2, 1)
      pset(dx[d] - 1, dy[d] - 1, 12)
    end
  end
end

function fx.clear()
  alive = 0
  for d = 1, MAX do dt[d] = -1 end
end

return fx
