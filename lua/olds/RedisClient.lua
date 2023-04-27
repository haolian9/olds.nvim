local M = {}

local uv = vim.loop
local protocol = require("olds.protocol")

---@class olds.Reply
---@field data any
---@field err string?

local forever = math.pow(2, 31) - 1

---@class olds.Client
---@field state {sock: any, closed: boolean, reply: olds.Reply}
local Client = {}
do
  ---@param cmd string
  ---@param ... string|number
  ---@return olds.Reply
  function Client:send(cmd, ...)
    assert(not self.state.closed)
    local packed = protocol.pack(cmd, ...)
    -- todo: what should be done for the result of uv.write
    local _ = uv.write(self.state.sock, packed, function(err) assert(err == nil, err) end)
    vim.wait(forever, function() return self.state.closed or self.state.reply ~= nil end, 75)
    if self.state.reply ~= nil then
      local reply = self.state.reply
      self.state.reply = nil
      return reply
    end
    if self.state.closed then error("connection closed") end
    -- could be ctrl-c by user
    error("unreachable: unexpected situation")
  end

  function Client:close()
    uv.close(self.state.sock, function(err)
      self.state.closed = true
      assert(err == nil, err)
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
      error(err)
    end
  end)

  uv.read_start(sock, function(err, data)
    if err then
      error("unreachable: unexpected error: " .. err)
    elseif data then
      local unpacked_data, request_err = protocol.unpack(data)
      state.reply = { data = unpacked_data, err = request_err }
    else
      state.closed = true
    end
  end)

  return setmetatable({ state = state }, { __index = Client })
end

function M.connect_tcp(ip, port)
  local _, _ = ip, port
  error("not implemented")
end

return M
