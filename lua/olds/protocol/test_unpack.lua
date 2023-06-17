---@diagnostic disable: invisible

local fn = require("infra.fn")

local unpack = require("olds.protocol.unpack")
local Stash = require("olds.protocol.Stash")

local co = coroutine

local function assert_have_none(expect_err, ok, have_one, err)
  assert(ok)
  assert(not have_one)
  assert(err == expect_err)
end

local function assert_have_one(expect_data, ok, have_one, data, err)
  assert(ok)
  assert(have_one)
  assert(err == nil)
  assert(data == expect_data)
end

local function assert_have_list(expect_list, ok, have_one, data, err)
  assert(ok)
  assert(have_one)
  assert(err == nil)
  assert(type(data) == "table")
  assert(fn.iter_equals(data, expect_list))
end

local function assert_have_error(expect_err, ok, have_one, data, err)
  assert(ok)
  assert(have_one)
  assert(data == nil)
  assert(err == expect_err)
end

do -- main
  local stash = Stash()
  local unpacker = unpack(stash)

  assert_have_none("wait for new data", co.resume(unpacker))

  do
    stash:clear()

    stash:push("-ERR unknown command 'hello'\r\n")
    assert_have_error("ERR unknown command 'hello'", co.resume(unpacker))

    stash:push("+OK\r\n")
    assert_have_one("OK", co.resume(unpacker))

    stash:push(":99\r\n")
    assert_have_one(99, co.resume(unpacker))

    stash:push(":-1\r\n")
    assert_have_one(-1, co.resume(unpacker))

    stash:push("$5\r\nhello\r\n")
    assert_have_one("hello", co.resume(unpacker))

    stash:push("$0\r\n\r\n")
    assert_have_one("", co.resume(unpacker))

    stash:push("$-1\r\n")
    assert_have_one(nil, co.resume(unpacker))
  end

  do
    stash:clear()
    stash:push("*2\r\n$5\r\nhello\r\n$5\r\nworld\r\n")
    assert_have_list({ "hello", "world" }, co.resume(unpacker))
  end

  do
    stash:clear()
    stash:push("*2\r\n$5\r\nhello\r\n$5\r\nworld\r\n")
    stash:push("$-1\r\n")
    stash:push("$0\r\n\r\n")
    assert_have_list({ "hello", "world" }, co.resume(unpacker))
    assert_have_one(nil, co.resume(unpacker))
    assert_have_one("", co.resume(unpacker))
  end
end
