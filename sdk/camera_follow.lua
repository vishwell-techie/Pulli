-- camera_follow.lua — a camera that keeps something on screen.
--
--   local follow = require("camera_follow")
--   local cam = follow.new()
--   cam:bounds(0, 0, map_w, map_h)      -- never show past the map's edges
--   cam:snap(player.x, player.y)        -- start centred on the player
--
--   function update(dt)
--     cam:update(player.x, player.y, dt)
--   end
--
--   function draw()
--     cam:apply()                       -- then draw the world
--     map.draw(0)
--     spr(1, player.x, player.y)
--     camera()                          -- then the screen: score, hearts
--   end
--
-- follow.new(options)   A camera. Options, all optional:
--     smooth  how quickly it catches up; higher is snappier, 0 is instant (8)
--     dead_w, dead_h   size of the box in mid-screen inside which the target
--                      can move without the camera moving at all (0, 0)
--     view_w, view_h   size of the view (320, 240)
-- cam:update(x, y, dt)  Follow the point (x, y). Call once a frame.
-- cam:snap(x, y)        Centre on (x, y) at once: for the start of a level.
-- cam:bounds(x, y, w, h)   Keep the view inside this rectangle. With no
--                          arguments, remove the limit.
-- cam:shake(pixels, seconds)   Shake by up to `pixels`, fading out.
-- cam:apply()           Set the drawing camera. Call at the top of draw().
-- cam.x, cam.y          The view's top-left corner, to read.
--
-- This file is part of the Pulli SDK. Copy it into your game and change it
-- as you like.

local follow = {}
local Camera = {}
Camera.__index = Camera

function follow.new(options)
  options = options or {}
  local cam = setmetatable({}, Camera)
  cam.x, cam.y = 0, 0
  cam.smooth = options.smooth or 8
  cam.dead_w, cam.dead_h = options.dead_w or 0, options.dead_h or 0
  cam.view_w, cam.view_h = options.view_w or 320, options.view_h or 240
  cam.min_x, cam.min_y, cam.max_x, cam.max_y = nil, nil, nil, nil
  cam.shake_size, cam.shake_left, cam.shake_time = 0, 0, 1
  cam.shake_x, cam.shake_y = 0, 0
  return cam
end

local function clamp(v, lo, hi)
  if hi < lo then return (lo + hi) / 2 end      -- the limit is smaller than the view: centre it
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Keep the view inside the bounds, if there are any.
local function hold(cam)
  if cam.min_x then
    cam.x = clamp(cam.x, cam.min_x, cam.max_x - cam.view_w)
    cam.y = clamp(cam.y, cam.min_y, cam.max_y - cam.view_h)
  end
end

function Camera:bounds(x, y, w, h)
  if x == nil then
    self.min_x = nil
  else
    self.min_x, self.min_y, self.max_x, self.max_y = x, y, x + w, y + h
  end
  hold(self)
end

function Camera:snap(x, y)
  self.x, self.y = x - self.view_w / 2, y - self.view_h / 2
  hold(self)
end

-- Where the view would have to be to bring `at` back inside the dead zone.
local function wanted(view, size, dead, at)
  local centre = view + size / 2
  if at < centre - dead / 2 then return at + dead / 2 - size / 2 end
  if at > centre + dead / 2 then return at - dead / 2 - size / 2 end
  return view
end

function Camera:update(x, y, dt)
  local goal_x = wanted(self.x, self.view_w, self.dead_w, x)
  local goal_y = wanted(self.y, self.view_h, self.dead_h, y)
  local step = self.smooth <= 0 and 1 or math.min(1, self.smooth * dt)
  self.x = self.x + (goal_x - self.x) * step
  self.y = self.y + (goal_y - self.y) * step
  hold(self)

  if self.shake_left > 0 then
    self.shake_left = self.shake_left - dt
    if self.shake_left > 0 then
      local size = self.shake_size * self.shake_left / self.shake_time     -- fades as it runs out
      self.shake_x = (math.random() * 2 - 1) * size
      self.shake_y = (math.random() * 2 - 1) * size
    else
      self.shake_x, self.shake_y = 0, 0
    end
  end
end

function Camera:shake(pixels, seconds)
  self.shake_size, self.shake_left, self.shake_time = pixels, seconds, seconds
end

function Camera:apply()
  camera(self.x + self.shake_x, self.y + self.shake_y)
end

return follow
