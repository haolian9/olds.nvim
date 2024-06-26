---drived from vim.ringbuf with some changes
---* names: read, write
---* error on full

---@class olds.RingBuf
---@field items unknown[]
---@field size integer
---@field idx_read integer
---@field idx_write integer
local Impl = {}
Impl.__index = Impl

---@param item any
function Impl:write(item)
  local next = (self.idx_write + 1) % self.size
  if next == self.idx_read then error("full") end

  self.items[self.idx_write] = item
  self.idx_write = next
end

---@return unknown?
function Impl:read()
  if self.idx_read == self.idx_write then return end

  local idx = self.idx_read
  local item = self.items[idx]
  self.items[idx] = nil
  self.idx_read = (idx + 1) % self.size
  return item
end

---@param size integer
---@return olds.RingBuf
return function(size) return setmetatable({ items = {}, size = size + 1, idx_read = 0, idx_write = 0 }, Impl) end
