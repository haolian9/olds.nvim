local ffi = require("ffi")
local jelly = require("infra.jellyfish")("olds")
local fs = require("infra.fs")
local fn = require("infra.fn")

ffi.cdef([[
  bool redis_connect_unix(const char *path);
  bool redis_connect_ip(const char *ip, uint16_t port);
  void redis_close();

  bool redis_del(const char *key);
  bool redis_ping();
  typedef struct { double score; const char *value; } ZaddMember;
  int64_t redis_zadd(const char *key, const ZaddMember *const *members, size_t len);
  int64_t redis_zcard(const char *key);
  int64_t redis_zremrangebyrank(const char *key, int64_t start, int64_t stop);

  bool redis_zrevrange_to_file(const char *key, int64_t start, int64_t stop, const char *path);
]])

local M = {}

local libredis
local ZaddMember
do
  local path = fs.joinpath(fs.resolve_plugin_root("olds", "redis.lua"), "../..", "zig-out/lib/libredis.so")
  libredis = ffi.load(path, false)
  ZaddMember = ffi.typeof("ZaddMember")
end

local state = {
  connected = false,
}

function M.connect_unix(path)
  if state.connected then return jelly.err("re-creating redis connection") end
  local ok = libredis.redis_connect_unix(path)
  if ok then state.connected = true end
  return ok
end

function M.connect_ip(ip, port)
  if state.connected then return jelly.err("re-creating redis connection") end
  local ok = libredis.redis_connect_ip(ip, port)
  if ok then state.connected = true end
  return ok
end

function M.close()
  assert(state.connected)
  libredis.redis_close()
  state.connected = false
end

function M.ping()
  assert(state.connected)
  return libredis.redis_ping()
end

---@param key string
---@param ... number|string [score member]+
---@return number
function M.zadd(key, ...)
  assert(state.connected)

  local args = { ... }
  assert(#args % 2 == 0)
  local len = #args / 2
  assert(len > 0)

  local members
  do
    members = ffi.new("const ZaddMember *[?]", len)
    local iter = fn.iterate(args)
    for i = 0, len - 1 do
      members[i] = ZaddMember(assert(iter()), assert(iter()))
    end
  end

  return libredis.redis_zadd(key, members, len)
end

---@param key string
---@return boolean
function M.del(key)
  assert(state.connected)
  return libredis.redis_del(key)
end

---@param key string
---@param start number
---@param stop number
---@param outfile string absolute path
---@return boolean
function M.zrevrange_to_file(key, start, stop, outfile)
  assert(state.connected)
  assert(fs.is_absolute(outfile))
  return libredis.redis_zrevrange_to_file(key, start, stop, outfile)
end

---@param key string
---@return number
function M.zcard(key)
  assert(state.connected)
  return assert(tonumber(libredis.redis_zcard(key)))
end

---@param key string
---@param start number 0-based, inclusive
---@param stop number 0-based, inclusive
---@return number
function M.zremrangebyrank(key, start, stop)
  assert(state.connected)
  return assert(tonumber(libredis.redis_zremrangebyrank(key, start, stop)))
end

return M
