local M = {}

local listlib = require("infra.listlib")
local logging = require("infra.logging")

local protocol = require("olds.protocol")

local uv = vim.loop
local co = coroutine

local log = logging.newlogger("RedisClient", "info")

---@class olds.Reply
---@field data? string|number|string[]
---@field err? string

local FOREVER = math.pow(2, 31) - 1

local function fatal(fmt, ...)
  if select("#", ...) == 0 then
    error(fmt)
  else
    error(string.format(fmt, ...))
  end
end

---@class olds.Client
---@field private sock any
---@field private closed boolean
---@field private replies olds.Reply[]
---@field private stash olds.protocol.Stash
---@field private unpacker thread
local Client = {}
do
  Client.__index = Client

  ---@param cmd string
  ---@param ... string|number
  ---@return olds.Reply
  function Client:send(cmd, ...)
    assert(not self.closed)
    local packed = protocol.pack(cmd, ...)
    uv.write(self.sock, packed, function(err)
      if err ~= nil then fatal("write error: %s", err) end
    end)
    vim.wait(FOREVER, function() return self.closed or #self.replies > 0 end, 75)
    if #self.replies > 0 then return listlib.pop(self.replies) end
    if self.closed then fatal("connection closed during round trip") end
    -- could be ctrl-c by user
    error("unreachable: unexpected situation")
  end

  function Client:close()
    uv.close(self.sock, function(err)
      self.closed = true
      if err ~= nil then fatal("close error: %s", err) end
    end)
  end

  function Client:recv(rawdata)
    self.stash:push(rawdata)
    while true do
      local _, have_one, data, errdata = assert(co.resume(self.unpacker))
      if have_one then
        listlib.push(self.replies, { data = data, err = errdata })
      else
        if data == "wait for new data" then return end
        do -- crash on unexpected errors
          Client:close()
          fatal(data)
        end
      end
    end
  end
end

---@param sockpath string
---@return olds.Client
function M.connect_unix(sockpath)
  ---@diagnostic disable: invisible

  local client
  do
    local state = {}
    do
      state.sock = assert(uv.new_pipe())
      state.closed = nil
      state.replies = {}
      state.stash = protocol.Stash()
      state.unpacker = protocol.unpack(state.stash)
    end

    client = setmetatable(state, Client)
  end

  uv.pipe_connect(client.sock, sockpath, function(err)
    if err == nil then
      client.closed = false
    else
      client.closed = true
      fatal("establish error: %s", err)
    end
  end)

  uv.read_start(client.sock, function(err, data)
    if err then
      fatal("read error: %s", err)
    elseif data then
      log.debug("%s\n", data)
      client:recv(data)
    else
      client.closed = true
    end
  end)

  return client
end

function M.connect_tcp(ip, port)
  local _, _ = ip, port
  error("not implemented")
end

return M
