---@diagnostic disable: invisible

local fn = require("infra.fn")

local Stash = require("olds.protocol.Stash")

local co = coroutine

local function assert_have_none(expect_err, ...)
  local args = { ... }
  assert(#args == 3)
  local ok, have_one, err = unpack(args)
  assert(ok)
  assert(not have_one)
  assert(err == expect_err)
end

---@param a string[]
---@param ... string
local function assert_list(a, ...) assert(fn.iter_equals(a, { ... })) end

do -- main
  local stash = Stash()

  do
    stash:clear()
    local peeker = stash:peekn(3)
    assert_have_none("wait for new data", co.resume(peeker))
    stash:push("+")
    assert_have_none("wait for new data", co.resume(peeker))
    stash:push("OK\r\n")
    local ok, finished, data = co.resume(peeker)
    assert(ok and finished)
    assert_list(data, "+", "OK")
  end

  do
    stash:clear()
    local poper = stash:popn(3)
    assert_have_none("wait for new data", co.resume(poper))
    stash:push("+")
    assert_have_none("wait for new data", co.resume(poper))
    stash:push("OK\r\n")
    local ok, finished, data = co.resume(poper)
    assert(ok and finished)
    assert_list(data, "+", "OK")
    assert_list(stash.store, "\r\n")
  end

  do
    stash:clear()
    local peeker = stash:peekuntil("\r\n")
    assert_have_none("wait for new data", co.resume(peeker))
    stash:push("+")
    assert_have_none("wait for new data", co.resume(peeker))
    stash:push("OK\r\nx")
    local ok, finished, data = co.resume(peeker)
    assert(ok and finished)
    assert_list(data, "+", "OK\r\n")
  end

  do
    stash:clear()
    local poper = stash:popuntil("\r\n")
    assert_have_none("wait for new data", co.resume(poper))
    stash:push("+")
    assert_have_none("wait for new data", co.resume(poper))
    stash:push("OK\r\nx")
    local ok, finished, data = co.resume(poper)
    assert(ok and finished)
    assert_list(data, "+", "OK\r\n")
    assert_list(stash.store, "x")
  end
end
