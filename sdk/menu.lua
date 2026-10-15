-- menu.lua — a list to choose from.
--
--   local menu = require("menu")
--   local main = menu.new({ "Start", "Options", "Quit" }, {
--     x = 120, y = 100,
--     choose = function(i, item) if item == "Start" then scene.go("play") end end,
--   })
--
--   function update(dt) main:update() end
--   function draw()     main:draw() end
--
-- Up and down move the highlight (held, they repeat), wrapping from the end
-- to the start. A chooses; B calls `back`, if given.
--
-- menu.new(items, options)   A menu of `items`, a list of text in English,
--     Tamil or both (rows are as far apart as the tallest item needs). Options:
--     x, y       top-left corner (8, 8)
--     rows       how many items show at once; more scroll (all of them)
--     choose     function(index, item) called when one is chosen
--     back       function() called when B is pressed
--     wrap       false to stop at the ends instead of wrapping (true)
--     box        draw a box behind the menu (true)
--     colors     back, border, text, picked
-- m:update()      Read the buttons. Returns the index chosen this frame, if any.
-- m:draw()        Draw it.
-- m.selected      The highlighted index; set it to move the highlight.
-- m:set_items(items)   Replace the list, keeping the highlight where it can.
--
-- This file is part of the Pulli SDK. Copy it into your game to change it.

local menu = {}
local Menu = {}
Menu.__index = Menu

local GAP, PAD = 2, 6                 -- rows are the tallest item plus GAP apart

function menu.new(items, options)
  options = options or {}
  local m = setmetatable({}, Menu)
  m.x, m.y = options.x or 8, options.y or 8
  m.rows = options.rows
  m.choose, m.back = options.choose, options.back
  m.wrap = options.wrap ~= false
  m.box = options.box ~= false
  m.colors = options.colors or { back = 32, border = 7, text = 7, picked = 10 }
  m.selected, m.first = 1, 1
  m.a_was, m.b_was = true, true             -- a button already down does not count
  m:set_items(items)
  return m
end

function Menu:set_items(items)
  if type(items) ~= "table" or #items == 0 then error("menu: give at least one item", 2) end
  self.items = items
  self.width, self.line = 0, 0
  for i = 1, #items do
    local w, h = text_size(tostring(items[i]))
    self.width, self.line = math.max(self.width, w), math.max(self.line, h + GAP)
  end
  self.selected = math.min(self.selected, #items)
  self:scroll()
end

-- Keep the highlighted item inside the rows that show.
function Menu:scroll()
  local rows = math.min(self.rows or #self.items, #self.items)
  if self.selected < self.first then self.first = self.selected end
  if self.selected > self.first + rows - 1 then self.first = self.selected - rows + 1 end
  self.first = math.max(1, math.min(self.first, #self.items - rows + 1))
end

function Menu:update()
  local n = #self.items
  if btnp("up") then
    self.selected = self.selected > 1 and self.selected - 1 or (self.wrap and n or 1)
  elseif btnp("down") then
    self.selected = self.selected < n and self.selected + 1 or (self.wrap and 1 or n)
  end
  self:scroll()

  -- A and B count once per press, unlike btnp(), which repeats.
  local a, b = btn("a"), btn("b")
  local chose, went_back = a and not self.a_was, b and not self.b_was
  self.a_was, self.b_was = a, b
  if went_back and self.back then self.back() end
  if chose then
    if self.choose then self.choose(self.selected, self.items[self.selected]) end
    return self.selected
  end
end

function Menu:draw()
  local c = self.colors
  local rows = math.min(self.rows or #self.items, #self.items)
  local w, h = self.width + 16 + 2 * PAD, rows * self.line + 2 * PAD - 2
  if self.box then
    rectfill(self.x, self.y, w, h, c.back)
    rect(self.x, self.y, w, h, c.border)
  end
  for row = 1, rows do
    local i = self.first + row - 1
    local ty = self.y + PAD + (row - 1) * self.line
    local picked = i == self.selected
    if picked then print(">", self.x + PAD, ty + (self.line - GAP - 8) // 2, c.picked) end
    print(tostring(self.items[i]), self.x + PAD + 16, ty, picked and c.picked or c.text)
  end
  if self.first > 1 then print("^", self.x + w - 12, self.y + 2, c.border) end
  if self.first + rows - 1 < #self.items then print("v", self.x + w - 12, self.y + h - 10, c.border) end
end

return menu
