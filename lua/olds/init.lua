local M = {}

local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("olds")
local popup = require("infra.popup")
local bufrename = require("infra.bufrename")

local redis_client = require("olds.redis_client")

local api = vim.api
local uv = vim.loop

local facts = {
  aug = api.nvim_create_augroup("olds", {}),
  global_zset = string.format("%s:nvim:olds:global", uv.getuid()),
  history_size = 200,
}

local state = {
  has_setup = false,
  ---@type (number|string)[] odd: access-time; even: absolute path
  history = {},
}

---@param bufnr number
---@return string? absolute path
local function resolve_fpath(bufnr)
  -- a 'regular file' buffer
  if api.nvim_buf_get_option(bufnr, "buftype") ~= "" then return end
  local bufname = api.nvim_buf_get_name(bufnr)
  -- named
  if bufname == "" then return end
  -- plugin
  if string.find(bufname, "://", nil, true) then return end
  -- /tmp
  if vim.startswith(bufname, "/tmp/") then return end
  -- .git/COMMIT_EDITMSG
  if string.find(bufname, "/.git/", nil, true) then return end

  if fs.is_absolute(bufname) then return bufname end
  return vim.fn.expand("%:p", bufname)
end

--necessary setup
function M.setup(sock_path)
  if state.has_setup then return end

  if not redis_client.connect_unix(sock_path) then return jelly.err("unable connect to redis") end
  state.has_setup = true
end

--register autocmds to record and save oldfiles automatically
function M.auto()
  assert(state.has_setup)

  -- learnt these timings from https://github.com/ii14/dotfiles/blob/master/.config/nvim/lua/mru.lua
  api.nvim_create_autocmd({ "bufenter", "bufwritepost" }, {
    group = facts.aug,
    callback = function(args)
      assert(state.has_setup)
      local bufnr = args.buf
      local path = resolve_fpath(bufnr)
      if path == nil then return end
      local time = os.time()
      table.insert(state.history, time)
      table.insert(state.history, path)
    end,
  })
  api.nvim_create_autocmd({ "focuslost", "vimsuspend", "vimleavepre" }, {
    group = facts.aug,
    callback = function()
      assert(state.has_setup)
      local hist = state.history
      if #hist == 0 then return end
      state.history = {}
      local n = redis_client.zadd(facts.global_zset, unpack(hist))
      jelly.debug("added %d records", n)
    end,
  })
  api.nvim_create_autocmd("vimleave", {
    group = facts.aug,
    callback = function()
      assert(state.has_setup)
      assert(#state.history == 0)
      -- honor the history_size
      local pop = redis_client.zcard(facts.global_zset)
      if pop > facts.history_size then redis_client.zremrangebyrank(facts.global_zset, 0, pop - facts.history_size - 1) end
      redis_client.close()
    end,
  })
end

--show oldfiles in a floatwin
---@param n number?
function M.oldfiles(n)
  assert(state.has_setup)
  local stop
  if n == nil then
    stop = 100 - 1
  elseif n == -1 then
    stop = -1
  else
    stop = n - 1
  end

  -- todo: show access-time
  local history
  local elapsed_ns
  do
    local ben_start = uv.hrtime()
    history = redis_client.zrevrange(facts.global_zset, 0, stop)
    if history == nil then return end
    elapsed_ns = uv.hrtime() - ben_start
  end

  local bufnr
  do
    bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    api.nvim_buf_set_lines(bufnr, 0, 1, false, { string.format("(elapsed %.3f ms)", elapsed_ns / 1000000), "" })
    api.nvim_buf_set_lines(bufnr, 2, -1, false, history)
    bufrename(bufnr, "olds://history")
  end

  do
    local width, height, top_row, left_col = popup.coordinates(0.8, 0.8)
    -- stylua: ignore
    api.nvim_open_win(bufnr, true, {
      relative = 'editor', style = 'minimal',
      row = top_row, col = left_col, width = width, height = height,
    })
  end
end

return M
