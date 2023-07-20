local M = {}

local bufrename = require("infra.bufrename")
local fn = require("infra.fn")
local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("olds", "debug")
local popupgeo = require("infra.popupgeo")
local prefer = require("infra.prefer")
local strlib = require("infra.strlib")

local RedisClient = require("olds.RedisClient")

local api = vim.api
local uv = vim.loop

local facts = {}
do
  facts.augrp = api.nvim_create_augroup("olds", {})
  local uid = uv.getuid()
  facts.ranks_id = string.format("%s:nvim:olds:ranks", uid)
  ---a redis hash; field={path}, value=‘{line}:{col}’
  facts.pos_id = string.format("%s:nvim:olds:poses", uid)
  ---@type fun():olds.Client
  facts.client_factory = nil
end

local contracts = {}
do
  ---@param bufnr number
  ---@return string? absolute path
  function contracts.resolve_fpath(bufnr)
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
  ---pattern='{path}:{line}:{col}'; line and col start from 0
  ---@param pos string
  ---@return integer,integer @line, col
  function contracts.parse_pos(pos)
    local line, col = string.match(pos, [[^%d+:%d+$]])
    assert(line and col)
    line = assert(tonumber(line))
    col = assert(tonumber(col))
    return line, col
  end
  ---@param line integer @start from 0
  ---@param col integer @start from 0
  ---@return string
  function contracts.format_pos(line, col) return string.format("%d:%d", line, col) end
end

---@type olds.Client
local client = setmetatable({}, {
  __index = function(t, k)
    local v
    if k == "host" then
      --todo: reconnect
      v = assert(facts.client_factory)()
    else
      v = function(_, ...) return t.host[k](t.host, ...) end
    end
    t[k] = v
    return v
  end,
})

local history = {}
do
  ---@private
  ---@type {[string]: {last_seen: integer, line: integer, col: integer}}
  history.records = {}

  ---@param winid integer
  function history:record(winid)
    local bufnr = api.nvim_win_get_buf(winid)
    local path = contracts.resolve_fpath(bufnr)
    if path == nil then return end
    local cursor = api.nvim_win_get_cursor(winid)
    self.records[path] = { last_seen = os.time(), line = cursor[1] - 1, col = cursor[2] }
  end

  function history:persist()
    local records
    do
      records = self.records
      self.records = {}
      if next(records) == nil then return end
    end
    do -- ranks
      local ranks = {}
      for path, record in pairs(records) do
        table.insert(ranks, record.last_seen)
        table.insert(ranks, path)
      end
      local reply = client:send("ZADD", facts.ranks_id, unpack(ranks))
      assert(reply.err == nil, reply.err)
      jelly.debug("updated %d records", reply.data)
    end
    do -- poses
      local poses = {}
      for path, record in pairs(records) do
        table.insert(poses, path)
        table.insert(poses, contracts.format_pos(record.line, record.col))
      end
      local reply = client:send("HSET", facts.pos_id, unpack(poses))
      assert(reply.err == nil, reply.err)
      jelly.debug("updated %d poses", reply.data)
    end
  end
end

---@param sockpath string @the absolute path to redis unix socket
function M.setup(sockpath)
  assert(sockpath)
  facts.client_factory = function() return RedisClient.connect_unix(sockpath) end
end

function M.init()
  M.init = nil

  api.nvim_create_autocmd("bufwinleave", {
    group = facts.augrp,
    callback = function() history:record(api.nvim_get_current_win()) end,
  })

  api.nvim_create_autocmd("vimleavepre", {
    group = facts.augrp,
    callback = function()
      for _, winid in ipairs(api.nvim_list_wins()) do
        history:record(winid)
      end
    end,
  })

  api.nvim_create_autocmd({ "focuslost", "vimleave" }, {
    group = facts.augrp,
    callback = function() history:persist() end,
  })
end

--show the whole history in a floatwin
function M.oldfiles()
  local records, elapsed_ns
  do
    local ben_start = uv.hrtime()
    local reply = client:send("ZRANGE", facts.ranks_id, 0, -1, "REV")
    assert(reply.err == nil, reply.err)
    records = reply.data
    elapsed_ns = uv.hrtime() - ben_start
    assert(type(records) == "table")
  end

  local bufnr
  do
    bufnr = api.nvim_create_buf(false, true)
    prefer.bo(bufnr, "bufhidden", "wipe")
    api.nvim_buf_set_lines(bufnr, 0, 1, false, { string.format("(elapsed %.3f ms)", elapsed_ns / 1000000), "" })
    api.nvim_buf_set_lines(bufnr, 2, -1, false, records)
    bufrename(bufnr, "olds://history")
  end

  do
    local width, height, top_row, left_col = popupgeo.editor_central(0.8, 0.8)
    api.nvim_open_win(bufnr, true, { relative = "editor", style = "minimal", row = top_row, col = left_col, width = width, height = height })
  end
end

---dump the whole history into the given file
---@param outfile string
---@return boolean
function M.dump(outfile)
  local paths
  do
    local reply = client:send("ZRANGE", facts.ranks_id, 0, -1, "REV")
    assert(reply.err == nil, reply.err)
    paths = reply.data
    assert(type(paths) == "table")
  end

  local poses
  do
    local reply = client:send("HMGET", facts.pos_id, unpack(paths))
    assert(reply.err == nil, reply.err)
    poses = reply.data
    assert(type(poses) == "table")
    --there could be holes in this lua-table
    assert(#poses == #paths)
  end

  do
    local file = assert(io.open(outfile, "w"))
    local ok, err = pcall(function()
      local function fmt(zip) return string.format("%s:%s", zip[1], zip[2]) end
      for batch in fn.batch(fn.zip(paths, poses), 256) do
        local line = fn.join(fn.map(fmt, batch), "\n")
        file:write(line)
        file:write("\n")
      end
    end)
    file:close()
    assert(ok, err)
  end

  return true
end

---reset the history
function M.reset()
  local reply = client:send("DEL", facts.ranks_id, facts.pos_id)
  assert(reply.err == nil, reply.err)
end

---prune those files were deleted already
function M.prune()
  local records
  do
    local reply = client:send("ZRANGE", facts.ranks_id, 0, -1, "rev")
    assert(reply.err == nil, reply.err)
    records = reply.data
    assert(type(records) == "table")
  end

  local running, danglings = #records, {}

  do
    -- todo: dealloc?
    local work = uv.new_work(
      ---@param fpath string
      function(fpath)
        local _, _, err = vim.loop.fs_stat(fpath)
        return fpath, err ~= "ENOENT"
      end,
      ---@param fpath string
      ---@param exists boolean
      function(fpath, exists)
        running = running - 1
        if exists then return end
        table.insert(danglings, fpath)
      end
    )
    for _, fpath in ipairs(records) do
      --todo: '{path}:{line}:{col}'
      uv.queue_work(work, fpath)
    end
  end

  do
    local timer = uv.new_timer()
    uv.timer_start(timer, 0, 250, function()
      if running > 0 then return end
      uv.timer_stop(timer)
      vim.schedule(function()
        if #danglings == 0 then return jelly.info("no need to prune") end
        do
          local reply = client:send("ZREM", facts.ranks_id, unpack(danglings))
          assert(reply.err == nil, reply.err)
          jelly.info("rm %s/%s members", reply.data, #danglings)
        end
        do
          local reply = client:send("HDEL", facts.pos_id, unpack(danglings))
          assert(reply.err == nil, reply.err)
          jelly.info("rm %s/%s poses", reply.data, #danglings)
        end
      end)
    end)
  end
end

return M
