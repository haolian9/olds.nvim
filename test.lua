local ffi = require("ffi")

ffi.cdef([[
  bool redis_connect_unix(const char *path);
  int64_t redis_zadd(const char *key, double score, const char *member);
  bool redis_del(const char *key);
  int64_t redis_zcard(const char *key);
  void redis_close();
  bool redis_zrange_to_file(const char *key, int64_t start, int64_t stop, const char *path);
]])

local libredis = ffi.load("/srv/playground/olds.nvim/zig-out/lib/libredis.so")

local function main()
  local key = "lua"
  print("connected?", libredis.redis_connect_unix("/run/user/1000/redis.sock"))
  for i = 1, 25 do
    libredis.redis_zadd(key, i, string.char(i + 96))
  end
  print("population?", libredis.redis_zcard(key))
  print("dumped?", libredis.redis_zrange_to_file(key, 0, 25, "/tmp/redis-lua.dump"))
  print("deleted?", libredis.redis_del(key))
  libredis.redis_close()
end

main()
