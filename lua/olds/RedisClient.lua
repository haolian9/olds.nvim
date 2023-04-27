local M = {}

local uv = vim.loop
local jelly = require("infra.jellyfish")("olds.ping", vim.log.levels.DEBUG)
local protocol = require("olds.protocol")

---@class olds.Reply
---@field data any
---@field err string?

local forever = math.pow(2, 31) - 1

function M.connect_unix(sockpath)
  local sock = assert(uv.new_pipe())

  local state = {
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

  ---@param cmd string
  ---@param ... string|number
  ---@return olds.Reply
  local function send(cmd, ...)
    assert(not state.closed)
    local packed = protocol.pack(cmd, ...)
    jelly.debug("packed: %s", vim.inspect(packed))
    -- todo: what should be done for the result of uv.write
    local _ = uv.write(sock, packed, function(err) assert(err == nil, err) end)
    vim.wait(forever, function() return state.closed or state.reply ~= nil end, 75)
    if state.reply ~= nil then
      local reply = state.reply
      state.reply = nil
      return reply
    end
    if state.closed then error("connection closed") end
    -- could be ctrl-c by user
    error("unreachable: unexpected situation")
  end

  local function close()
    uv.close(sock, function(err)
      state.closed = true
      assert(err == nil, err)
    end)
  end

  return {
    send = send,
    close = close,
  }
end

return M
