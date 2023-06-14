local M = {}

local uv = vim.loop
local protocol = require("olds.protocol")

---@class olds.Reply
---@field data any
---@field err string?

local FOREVER = math.pow(2, 31) - 1
local PIPE_BUF = 4096

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
---@field private reply olds.Reply
local Client = {}
do
  Client.__index = Client

  ---@param cmd string
  ---@param ... string|number
  ---@return olds.Reply
  function Client:send(cmd, ...)
    assert(not self.closed)
    local packed = protocol.pack(cmd, ...)
    -- todo: deal with this result
    local _ = uv.write(self.sock, packed, function(err)
      if err ~= nil then fatal("write error: %s", err) end
    end)
    vim.wait(FOREVER, function() return self.closed or self.reply ~= nil end, 75)
    if self.reply ~= nil then
      local reply = self.reply
      self.reply = nil
      return reply
    end
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
end

---@param sockpath string
---@return olds.Client
function M.connect_unix(sockpath)
  local sock = assert(uv.new_pipe())

  local state = {
    sock = sock,
    closed = nil,
    ---@type olds.Reply
    reply = nil,
  }

  -- todo: need to close this uv_connect_t?
  uv.pipe_connect(sock, sockpath, function(err)
    if err == nil then
      state.closed = false
    else
      state.closed = true
      fatal("establish error: %s", err)
    end
  end)

  uv.read_start(sock, function(err, data)
    if err then
      fatal("read error: %s", err)
    elseif data then
      if #data > PIPE_BUF * 16 then
        -- close the connection to avoid hanging reads
        Client.close(state)
        fatal("reply is too large, could be paged")
      else
        local unpacked_data, request_err = protocol.unpack(data)
        state.reply = { data = unpacked_data, err = request_err }
      end
    else
      state.closed = true
    end
  end)

  return setmetatable(state, Client)
end

function M.connect_tcp(ip, port)
  local _, _ = ip, port
  error("not implemented")
end

return M
