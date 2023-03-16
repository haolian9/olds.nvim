local ffi = require("ffi")

ffi.cdef([[
  bool redis_connect_unix(const char *path);
  bool redis_del(const char *key);
  int64_t redis_zcard(const char *key);
  void redis_close();
  bool redis_zrevrange_to_file(const char *key, int64_t start, int64_t stop, const char *path);

  typedef struct { double score; const char *value; } ZaddMember;
  int64_t redis_zadd(const char *key, const ZaddMember *const *members, size_t len);
]])

local libredis = ffi.load("/srv/playground/olds.nvim/zig-out/lib/libredis.so")

local function main()
  local key = "lua"
  print("connected?", libredis.redis_connect_unix("/run/user/1000/redis.sock"))

  do
    local ZaddMember = ffi.typeof("ZaddMember")
    local len = 5
    local mems = ffi.new("const ZaddMember *[?]", len)
    for i = 0, len - 1 do
      mems[i] = ZaddMember(i, string.char(i + 97))
    end
    libredis.redis_zadd(key, mems, len)
  end

  print("population?", libredis.redis_zcard(key))
  print("dumped?", libredis.redis_zrevrange_to_file(key, 0, 25, "/tmp/redis-lua.dump"))
  print("deleted?", libredis.redis_del(key))
  libredis.redis_close()
end

main()
