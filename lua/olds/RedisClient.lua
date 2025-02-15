local M = {}

local iuv = require("infra.iuv")
local jelly = require("infra.jellyfish")("olds.RedisClient", "debug")
local listlib = require("infra.listlib")
local logging = require("infra.logging")

local protocol = require("olds.protocol")

local uv = vim.uv
local co = coroutine

local log = logging.newlogger("RedisClient", "info")

---@class olds.Reply
---@field data? string|number|string[]
---@field err? string

local FOREVER = math.pow(2, 31) - 1

---@class olds.Client
---@field private sock userdata
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
    iuv.write(self.sock, packed, function(err)
      if err ~= nil then jelly.fatal("write error: %s", err) end
    end)
    vim.wait(FOREVER, function() return self.closed or #self.replies > 0 end, 75)
    if #self.replies > 0 then return listlib.pop(self.replies) end
    if self.closed then jelly.fatal("connection closed during round trip") end
    -- could be ctrl-c by user
    error("unreachable: unexpected situation")
  end

  function Client:close()
    uv.close(self.sock, function(err)
      self.closed = true
      if err ~= nil then jelly.fatal("close error: %s", err) end
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
          jelly.fatal(data)
        end
      end
    end
  end
end

do
  ---@param create_sock fun(client: olds.Client): userdata
  ---@return olds.Client
  local function create_client(create_sock)
    ---@diagnostic disable: invisible

    local state = {}
    do
      state.sock = nil
      state.closed = nil
      state.replies = {}
      state.stash = protocol.Stash()
      state.unpacker = protocol.unpack(state.stash)
    end

    local client = setmetatable(state, Client)

    client.sock = create_sock(client)

    iuv.read_start(client.sock, function(err, data)
      if err then
        jelly.fatal("read error: %s", err)
      elseif data then
        log.debug("%s\n", data)
        client:recv(data)
      else
        client.closed = true
      end
    end)

    return client
  end

  ---@param sockpath string
  ---@return olds.Client
  function M.connect_unix(sockpath)
    return create_client(function(client)
      local sock = assert(iuv.new_pipe())
      iuv.pipe_connect(sock, sockpath, function(err)
        if err == nil then
          client.closed = false
        else
          client.closed = true
          jelly.fatal("establish error: %s", err)
        end
      end)
      return sock
    end)
  end

  ---@param ip string
  ---@param port integer
  ---@return olds.Client
  function M.connect_tcp(ip, port)
    return create_client(function(client)
      local sock = assert(iuv.new_tcp())
      iuv.tcp_connect(sock, ip, port, function(err)
        if err == nil then
          client.closed = false
        else
          client.closed = true
          jelly.fatal("establish error: %s", err)
        end
      end)
      return sock
    end)
  end
end
return M
