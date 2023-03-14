local M = {}

local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("olds")

local redis = require("olds.redis")

local api = vim.api
local uv = vim.loop

local facts = {
  aug = api.nvim_create_augroup("olds", {}),
  global_zset = string.format("%s:nvim:olds:global", uv.getuid()),
  history_size = 200,
}

local state = {
  has_setup = false,
  history = {},
}

---@param bufnr number
---@return string?
local function resolve_fpath(bufnr)
  -- is a 'regular file' buffer
  if api.nvim_buf_get_option(bufnr, "buftype") ~= "" then return end
  local bufname = api.nvim_buf_get_name(bufnr)
  -- has been named
  if bufname == "" then return end
  if fs.is_absolute(bufname) then return bufname end
  return vim.fn.expand("%:p", bufname)
end

function M.setup(sock_path)
  if state.has_setup then return end

  if not redis.connect_unix(sock_path) then return jelly.err("unable connect to redis") end
  state.has_setup = true

  -- learnt these timings from https://github.com/ii14/dotfiles/blob/master/.config/nvim/lua/mru.lua
  api.nvim_create_autocmd({ "bufenter", "bufwritepost" }, {
    group = facts.aug,
    callback = function(args)
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
      local hist = state.history
      if #hist == 0 then return end
      state.history = {}
      redis.zadd(facts.global_zset, unpack(hist))
    end,
  })
  api.nvim_create_autocmd("vimleave", {
    group = facts.aug,
    callback = function()
      assert(state.has_setup)
      assert(#state.history == 0)
      -- honor the history_size
      local pop = redis.zcard(facts.global_zset)
      if pop > facts.history_size then redis.zremrangebyrank(facts.global_zset, 0, pop - facts.history_size - 1) end
      redis.close()
    end,
  })
end

return M
