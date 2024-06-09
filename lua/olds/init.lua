local M = {}

local augroups = require("infra.augroups")
local Ephemeral = require("infra.Ephemeral")
local fs = require("infra.fs")
local itertools = require("infra.itertools")
local its = require("infra.its")
local iuv = require("infra.iuv")
local jelly = require("infra.jellyfish")("olds")
local prefer = require("infra.prefer")
local rifts = require("infra.rifts")
local strlib = require("infra.strlib")
local wincursor = require("infra.wincursor")

local g = require("olds.g")

local api = vim.api
local uv = vim.uv

local facts = {}
do
  local uid = uv.getuid()
  facts.ranks_id = string.format("%s:nvim:olds:ranks", uid)
  ---a redis hash; field={path}, value=‘{lnum}:{col}’
  facts.pos_id = string.format("%s:nvim:olds:poses", uid)
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
    return vim.fn.fnamemodify(bufname, "%:p")
  end
  ---pattern='{path}:{lnum}:{col}'; lnum and col start from 0
  ---@param pos string
  ---@return integer,integer @lnum, col
  function contracts.parse_pos(pos)
    local lnum, col = string.match(pos, [[^%d+:%d+$]])
    assert(lnum and col)
    lnum = assert(tonumber(lnum))
    col = assert(tonumber(col))
    return lnum, col
  end
  ---@param lnum integer @start from 0
  ---@param col integer @start from 0
  ---@return string
  function contracts.format_pos(lnum, col) return string.format("%d:%d", lnum, col) end
end

---@type olds.Client
local client = setmetatable({}, {
  __index = function(t, k)
    local v
    if k == "host" then
      --todo: reconnect
      v = assert(g.create_client)()
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
  ---@type {[string]: {last_seen: integer, lnum: integer, col: integer}}
  history.records = {}

  ---@param winid integer
  function history:record(winid)
    local bufnr = api.nvim_win_get_buf(winid)
    local path = contracts.resolve_fpath(bufnr)
    if path == nil then return end
    local cursor = wincursor.position(winid)
    self.records[path] = { last_seen = os.time(), lnum = cursor.lnum, col = cursor.col }
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
        table.insert(poses, contracts.format_pos(record.lnum, record.col))
      end
      local reply = client:send("HSET", facts.pos_id, unpack(poses))
      assert(reply.err == nil, reply.err)
      jelly.debug("updated %d poses", reply.data)
    end
  end
end

function M.init()
  M.init = nil

  local aug = augroups.Augroup("olds://")
  aug:repeats("BufWinLeave", {
    callback = function() history:record(api.nvim_get_current_win()) end,
  })

  aug:repeats("VimLeavePre", {
    callback = function()
      for _, winid in ipairs(api.nvim_list_wins()) do
        history:record(winid)
      end
    end,
  })

  aug:repeats({ "FocusLost", "VimLeave" }, {
    group = facts.augrp,
    callback = function() history:persist() end,
  })
end

--show the whole history in a floatwin
function M.oldfiles()
  local records
  do
    local start_time = uv.hrtime()
    local reply = client:send("ZRANGE", facts.ranks_id, 0, -1, "REV")
    assert(reply.err == nil, reply.err)
    records = reply.data
    local elapsed_ns = uv.hrtime() - start_time
    assert(type(records) == "table")
    jelly.info("querying oldfiles took %.3fms", elapsed_ns / 1000000)
  end

  local bufnr = Ephemeral({ namepat = "olds://history/{bufnr}", handyclose = true }, records)

  rifts.open.fragment(bufnr, true, { relative = "editor" }, { width = 0.8, height = 0.8 })
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
  if #paths == 0 then
    poses = {}
  else
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
      for batch in itertools.batched(itertools.zip(paths, poses), 256) do
        local line = its(batch):map(fmt):join("\n")
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
    local work = uv.new_work(
      ---@param fpath string
      function(fpath)
        local exists = iuv.fs_stat(fpath) ~= nil
        return fpath, exists
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
      iuv.queue_work(work, fpath)
    end
  end

  do
    local timer = iuv.new_timer()
    iuv.timer_start(timer, 0, 250, function()
      if running > 0 then return end
      iuv.timer_stop(timer)
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

function M.ping()
  local reply = client:send("PING")
  assert(reply.err == nil, reply.err)
  assert(reply.data == "PONG")
  jelly.info("PONG")
end

return M
