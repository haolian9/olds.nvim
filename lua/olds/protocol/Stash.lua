local co = coroutine

-- todo: stash=['+OK\r', '\n'] peekuntil('\r\n')

---@class olds.protocol.Stash
---@field private store string[]
local Stash = {}
do
  Stash.__index = Stash

  ---@private
  function Stash:clear() self.store = {} end

  --pop n+0.5 lines
  ---@private
  ---@param full_n number?
  ---@param short_len number?
  ---@return string[]
  function Stash:pop(full_n, short_len)
    local popped = {}
    if full_n ~= nil then
      assert(full_n <= #self.store)
      for i = 1, full_n do
        popped[i] = table.remove(self.store, 1)
      end
    end
    if short_len ~= nil then
      local line = assert(self.store[1])
      table.insert(popped, string.sub(line, 1, short_len))
      self.store[1] = string.sub(line, short_len + 1)
    end
    return popped
  end

  --peek n+0.5 lines
  ---@private
  ---@param full_n number?
  ---@param short_len number?
  ---@return string[]
  function Stash:peek(full_n, short_len)
    local lines = {}
    if full_n ~= nil then
      assert(full_n <= #self.store)
      for i = 1, full_n do
        lines[i] = self.store[i]
      end
    end
    if short_len ~= nil then
      local line = assert(self.store[(full_n or 0) + 1])
      table.insert(lines, string.sub(line, 1, short_len))
    end
    return lines
  end

  ---@param data string
  function Stash:push(data) table.insert(self.store, data) end

  ---@param chars string
  ---@return thread
  function Stash:popuntil(chars)
    return co.create(function()
      local i = 0
      while true do
        if i < #self.store then
          i = i + 1
          local start, stop = string.find(self.store[i], chars, 1, true)
          if start ~= nil then return true, self:pop(i - 1, stop) end
        elseif i == #self.store then
          co.yield(false, "wait for new data")
        else
          error("unreachable: popuntil")
        end
      end
    end)
  end

  ---@param n number
  ---@return thread
  function Stash:popn(n)
    return co.create(function()
      local i = 0
      local remain = n
      while true do
        if i < #self.store then
          i = i + 1
          local llen = #self.store[i]
          if llen < remain then
            remain = remain - llen
          else
            return true, self:pop(i - 1, remain)
          end
        elseif i == #self.store then
          co.yield(false, "wait for new data")
        else
          error("unreachable: popn")
        end
      end
    end)
  end

  ---@param chars string
  ---@return thread
  function Stash:peekuntil(chars)
    return co.create(function()
      local i = 0
      while true do
        if i < #self.store then
          i = i + 1
          local start, stop = string.find(self.store[i], chars, 1, true)
          if start ~= nil then return true, self:peek(i - 1, stop) end
        elseif i == #self.store then
          co.yield(false, "wait for new data")
        else
          error("unreachable: peekuntil")
        end
      end
    end)
  end

  ---@param n number
  ---@return thread
  function Stash:peekn(n)
    return co.create(function()
      local i = 0
      local remain = n
      while true do
        if i < #self.store then
          i = i + 1
          local llen = #self.store[i]
          if llen < remain then
            remain = remain - llen
          else
            return true, self:peek(i - 1, remain)
          end
        elseif i == #self.store then
          co.yield(false, "wait for new data")
        else
          error("unreachable: peekn")
        end
      end
    end)
  end
end

---@return olds.protocol.Stash
return function() return setmetatable({ store = {} }, Stash) end
