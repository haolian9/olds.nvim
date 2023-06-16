local co = coroutine

---@class Stash
---@field private store string[]
---@field private pop fun(self: Stash, full_n?: number, short_len?: number): string[]
---@field private peek fun(self: Stash, full_n?: number, short_len?: number): string[]
local Stash = {}
do
  Stash.__index = Stash

  ---@param data string
  function Stash:push(data) table.insert(self.store, data) end
  function Stash:clear() self.store = {} end

  --pop n+0.5 lines
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
          error("unreachable")
        end
      end
    end)
  end

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
          error("unreachable")
        end
      end
    end)
  end

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
          error("unreachable")
        end
      end
    end)
  end

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
          error("unreachable")
        end
      end
    end)
  end
end

do -- test 1
  local function inspect(...) print(vim.inspect({ ... })) end

  local function assert_not_ok(expect_err, ...)
    local args = { ... }
    assert(#args == 3)
    local ok, finished, err = unpack(args)
    assert(ok)
    assert(not finished)
    assert(err == expect_err)
  end

  local stash = setmetatable({ store = {} }, Stash)

  if true then
    stash:clear()
    local peeker = stash:peekn(3)
    assert_not_ok("wait for new data", co.resume(peeker))
    stash:push("+")
    assert_not_ok("wait for new data", co.resume(peeker))
    stash:push("OK\r\n")
    local ok, finished, data = co.resume(peeker)
    assert(ok and finished)
    assert(data[1] == "+" and data[2] == "OK")
  end

  if true then
    stash:clear()
    local poper = stash:popn(3)
    assert_not_ok("wait for new data", co.resume(poper))
    stash:push("+")
    assert_not_ok("wait for new data", co.resume(poper))
    stash:push("OK\r\n")
    local ok, finished, data = co.resume(poper)
    assert(ok and finished)
    assert(#data == 2 and data[1] == "+" and data[2] == "OK")
    ---@diagnostic disable-next-line: invisible
    assert(#stash.store == 1 and stash.store[1] == "\r\n")
  end

  if true then
    stash:clear()
    local peeker = stash:peekuntil("\r\n")
    assert_not_ok("wait for new data", co.resume(peeker))
    stash:push("+")
    assert_not_ok("wait for new data", co.resume(peeker))
    stash:push("OK\r\nx")
    local ok, finished, data = co.resume(peeker)
    assert(ok and finished)
    assert(data[1] == "+" and data[2] == "OK\r\n")
  end

  if true then
    stash:clear()
    local poper = stash:popuntil("\r\n")
    assert_not_ok("wait for new data", co.resume(poper))
    stash:push("+")
    assert_not_ok("wait for new data", co.resume(poper))
    stash:push("OK\r\nx")
    local ok, finished, data = co.resume(poper)
    assert(ok and finished)
    assert(data[1] == "+" and data[2] == "OK\r\n")
    ---@diagnostic disable-next-line: invisible
    assert(#stash.store == 1 and stash.store[1] == "x")
  end
end
