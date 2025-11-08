local M = {}

local iuv = require("infra.iuv")
local jelly = require("infra.jellyfish")("olds.RedisClient", "info")
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

---@type {string: true}
local supported_cmds = {}
do
  --stylua: ignore start
  local list = {
    "ZADD", "ZRANGE", "ZREM",
    "HSET", "HMGET",
    "DEL", "HDEL",
    "PING",
  }
  --stylua: ignore end
  for _, cmd in ipairs(list) do
    supported_cmds[string.lower(cmd)] = true
    supported_cmds[string.upper(cmd)] = true
  end
end

---@alias olds.Client.ReqCallback fun(reply: olds.Reply)

---@class olds.Client
---@field private sock userdata
---@field private closed boolean
---@field private reqs {callback:olds.Client.ReqCallback}[]
---@field private stash olds.protocol.Stash
---@field private unpacker thread
local Client = {}
do
  Client.__index = Client

  ---@private
  ---@param callback olds.Client.ReqCallback
  ---@param cmd string
  ---@param ... string|number
  function Client:asend(callback, cmd, ...)
    assert(supported_cmds[cmd], "unsupported cmd")

    assert(not self.closed)
    local packed = protocol.pack(cmd, ...)
    iuv.write(self.sock, packed, function(err)
      if err ~= nil then jelly.fatal("RuntimeError", "write error: %s", err) end
      listlib.push(self.reqs, { callback = callback })
    end)
  end

  ---@param cmd string
  ---@param ... string|number
  ---@return olds.Reply
  function Client:send(cmd, ...)
    local done, reply = false, nil

    self:asend(function(r)
      done, reply = true, r
    end, cmd, ...)

    vim.wait(FOREVER, function() return self.closed or done end, 75, false)
    assert(reply ~= nil)

    return reply
  end

  function Client:close()
    if self.closed then return end
    uv.close(self.sock, function(err)
      self.closed = true
      if err ~= nil then jelly.fatal("RuntimeError", "close error: %s", err) end
    end)
  end

  ---@private
  function Client:recv(rawdata)
    self.stash:push(rawdata)
    while true do
      local _, have_one, data, errdata = assert(co.resume(self.unpacker))
      if have_one then
        local reply = { data = data, err = errdata }
        --todo: what if reply is for pubsub
        local req = assert(listlib.pop(self.reqs))
        vim.schedule(function() req.callback(reply) end)
      else
        if data == "wait for new data" then return end
        do -- crash on unexpected errors
          Client:close()
          jelly.fatal("RuntimeError", "%s", data)
        end
      end
    end
  end
end

---@param create_sock fun(client: olds.Client): userdata
---@return olds.Client
local function create_client(create_sock)
  ---@diagnostic disable: invisible

  local client
  do
    local state = { sock = nil, closed = nil, reqs = {} }
    state.stash = protocol.Stash()
    state.unpacker = protocol.unpack(state.stash)

    client = setmetatable(state, Client)
  end

  client.sock = create_sock(client)

  iuv.read_start(client.sock, function(err, data)
    if err then
      jelly.fatal("RuntimeError", "read error: %s", err)
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
        jelly.fatal("RuntimeError", "establish error: %s", err)
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
        jelly.fatal("RuntimeError", "establish error: %s", err)
      end
    end)
    return sock
  end)
end

return M
