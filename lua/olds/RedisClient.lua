local ffi = require("ffi")
local jelly = require("infra.jellyfish")("olds")
local fs = require("infra.fs")
local fn = require("infra.fn")

ffi.cdef([[
  uint64_t redis_client_size();
  typedef struct redisclient_t redisclient_t;
  redisclient_t *redis_connect_unix(char *vessal, const char *path);
  redisclient_t *redis_connect_ip(char *vessal, const char *ip, uint16_t port);
  void redis_close(redisclient_t *client);
  void redis_free(const char *reply);

  bool redis_del(redisclient_t *client, const char *key);
  bool redis_ping(redisclient_t *client);
  typedef struct { double score; const char *value; } ZaddMember;
  int64_t redis_zadd(redisclient_t *client, const char *key, const ZaddMember *const *members, size_t len);
  int64_t redis_zcard(redisclient_t *client, const char *key);
  int64_t redis_zremrangebyrank(redisclient_t *client, const char *key, int64_t start, int64_t stop);
  const char *redis_zrevrange(redisclient_t *client, const char *key, int64_t start, int64_t stop);

  bool redis_zrevrange_to_file(redisclient_t *client, const char *key, int64_t start, int64_t stop, const char *path);
]])

local clientlib
local ZaddMember
do
  local path = fs.joinpath(fs.resolve_plugin_root("olds", "RedisClient.lua"), "../..", "zig-out/lib/libredisclient.so")
  clientlib = ffi.load(path, false)
  ZaddMember = ffi.typeof("ZaddMember")
end

---@class olds.Client
local Client = { private = nil }
do
  function Client:client()
    return assert(self.private).client
  end

  function Client:close()
    clientlib.redis_close(self:client())
  end

  function Client:ping()
    return clientlib.redis_ping(self:client())
  end

  ---@param key string
  ---@param ... number|string [score member]+
  ---@return number
  function Client:zadd(key, ...)
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

    return clientlib.redis_zadd(self:client(), key, members, len)
  end

  ---@param key string
  ---@return boolean
  function Client:del(key)
    return clientlib.redis_del(self:client(), key)
  end

  ---@param key string
  ---@param start number
  ---@param stop number
  ---@param outfile string absolute path
  ---@return boolean
  function Client:zrevrange_to_file(key, start, stop, outfile)
    assert(fs.is_absolute(outfile))
    return clientlib.redis_zrevrange_to_file(self:client(), key, start, stop, outfile)
  end

  ---@param key string
  ---@return number
  function Client:zcard(key)
    return assert(tonumber(clientlib.redis_zcard(self:client(), key)))
  end

  ---@param key string
  ---@param start number 0-based, inclusive
  ---@param stop number 0-based, inclusive
  ---@return number
  function Client:zremrangebyrank(key, start, stop)
    return assert(tonumber(clientlib.redis_zremrangebyrank(self:client(), key, start, stop)))
  end

  ---@param key string
  ---@param start number
  ---@param stop number
  ---@return string[]?
  function Client:zrevrange(key, start, stop)
    local buf = clientlib.redis_zrevrange(self:client(), key, start, stop)
    local ok, result = pcall(function()
      return fn.split(ffi.string(buf), "\n")
    end)
    clientlib.redis_free(buf)
    if not ok then return jelly.err("ZREVRANGE: %s", assert(result)) end
    return result
  end
end

---@param private {vessal: any, client: any}
---@return olds.Client
local function new_client(private)
  return setmetatable({ private = private }, { __index = Client })
end

local M = {}

---@param path string
---@return olds.Client?
function M.connect_unix(path)
  assert(path and #path > 0)
  local vessal = ffi.new("char[?]", clientlib.redis_client_size())
  local client = clientlib.redis_connect_unix(vessal, path)
  if client then return new_client({ vessal = vessal, client = client }) end
end

---@param ip string
---@param port number
---@return olds.Client?
function M.connect_ip(ip, port)
  assert(ip and #ip > 0 and port)
  local vessal = ffi.new("char[?]", clientlib.redis_client_size())
  local client = clientlib.redis_connect_ip(vessal, ip, port)
  if client then return new_client({ vessal = vessal, client = client }) end
end

return M
