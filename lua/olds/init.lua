local M = {}

local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("olds")
local popupgeo = require("infra.popupgeo")
local bufrename = require("infra.bufrename")
local strlib = require("infra.strlib")
local prefer = require("infra.prefer")

local RedisClient = require("olds.RedisClient")

local api = vim.api
local uv = vim.loop

local facts = {
  aug = api.nvim_create_augroup("olds", {}),
  global_zset = string.format("%s:nvim:olds:global", uv.getuid()),
  history_size = 200,
  ---@type fun():olds.Client
  client_factory = nil,
}

local state = {
  ---@type olds.Client?
  _client = nil,
  ---@type (number|string)[] odd: access-time; even: absolute path
  _history = {},
}
do
  ---@private
  function state:client()
    if self._client == nil then
      local factory = assert(facts.client_factory, "olds.setup has not be called previously")
      -- todo: can not establish connection
      self._client = factory()
    end
    -- todo: dummy connection
    return assert(self._client)
  end

  function state:close_client()
    local client = self._client
    if client then client:close() end
  end

  function state:record_history(access_time, abspath)
    table.insert(self._history, access_time)
    table.insert(self._history, abspath)
  end

  function state:persist_history()
    local hist = self._history
    if #hist == 0 then return end
    self._history = {}
    local client = self:client()
    local reply = client:send("zadd", facts.global_zset, unpack(hist))
    assert(reply.err == nil, reply.err)
    jelly.debug("added %d records", reply.data)
  end

  function state:prune_history()
    local client = self:client()
    -- honor the history_size
    local total
    do
      local reply = client:send("zcard", facts.global_zset)
      assert(reply.err == nil, reply.err)
      total = tonumber(reply.data, 10)
    end
    if total > facts.history_size then
      local reply = client:send("zremrangebyrank", facts.global_zset, 0, total - facts.history_size - 1)
      assert(reply.err == nil, reply.err)
    end
  end
end

---@param bufnr number
---@return string? absolute path
local function resolve_fpath(bufnr)
  -- a 'regular file' buffer
  if prefer.bo(bufnr, "buftype") ~= "" then return end
  local bufname = api.nvim_buf_get_name(bufnr)
  -- named
  if bufname == "" then return end
  -- plugin
  if strlib.find(bufname, "://") then return end
  -- /tmp
  if strlib.startswith(bufname, "/tmp/") then return end
  -- .git/COMMIT_EDITMSG
  if strlib.find(bufname, "/.git/") then return end

  if fs.is_absolute(bufname) then return bufname end
  return vim.fn.expand("%:p", bufname)
end

function M.setup(...)
  local args = { ... }
  if #args == 1 then
    facts.client_factory = function() return RedisClient.connect_unix(args[1]) end
  elseif #args == 2 then
    facts.client_factory = function() return RedisClient.connect_tcp(args[1], args[2]) end
  else
    jelly.err("invalid arguments for creating RedisClient")
  end

  do --to record and save oldfiles
    -- learnt these timings from https://github.com/ii14/dotfiles/blob/master/.config/nvim/lua/mru.lua
    api.nvim_create_autocmd({ "bufenter", "bufwritepost" }, {
      group = facts.aug,
      callback = function(args)
        local bufnr = args.buf
        local path = resolve_fpath(bufnr)
        if path == nil then return end
        state:record_history(os.time(), path)
      end,
    })
    api.nvim_create_autocmd({ "focuslost", "vimsuspend", "vimleavepre" }, {
      group = facts.aug,
      callback = function() state:persist_history() end,
    })
    api.nvim_create_autocmd("vimleave", {
      group = facts.aug,
      callback = function()
        assert(#state._history == 0, "history should be persisted before vimleave")
        state:prune_history()
        state:close_client()
      end,
    })
  end
end

--show oldfiles in a floatwin
---@param n number?
function M.oldfiles(n)
  local stop
  if n == nil then
    stop = 100 - 1
  elseif n == -1 then
    stop = -1
  else
    stop = n - 1
  end

  local history
  local elapsed_ns
  do
    local ben_start = uv.hrtime()
    local reply = state:client():send("ZRANGE", facts.global_zset, 0, stop, "REV")
    assert(reply.err == nil, reply.err)
    history = reply.data
    if history == nil then return end
    elapsed_ns = uv.hrtime() - ben_start
  end

  local bufnr
  do
    bufnr = api.nvim_create_buf(false, true)
    prefer.bo(bufnr, "bufhidden", "wipe")
    api.nvim_buf_set_lines(bufnr, 0, 1, false, { string.format("(elapsed %.3f ms)", elapsed_ns / 1000000), "" })
    api.nvim_buf_set_lines(bufnr, 2, -1, false, history)
    bufrename(bufnr, "olds://history")
  end

  do
    local width, height, top_row, left_col = popupgeo.editor_central(0.8, 0.8)
    api.nvim_open_win(bufnr, true, { relative = "editor", style = "minimal", row = top_row, col = left_col, width = width, height = height })
  end
end

---@param outfile string
---@return boolean
function M.dump(outfile)
  local reply = state:client():send("ZRANGE", facts.global_zset, 0, -1, "REV")
  assert(reply.err == nil, reply.err)
  local history = reply.data
  do
    local file = assert(io.open(outfile, "w"))
    local ok, err = pcall(function() assert(file:write(table.concat(history, "\n"))) end)
    file:close()
    assert(ok, err)
  end
  return true
end

function M.reset()
  local reply = state:client():send("del", facts.global_zset)
  assert(reply.err == nil, reply.err)
end

return M
