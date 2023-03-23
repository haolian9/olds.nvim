
## features
* global MRU/old files
* data is stored in redis
* limited history size
* programming apis: for fond.nvim
* :oldfiles

## status
* it just works and is crash-prone

## prerequisites
* redis >= 6.* (okredis)
* nvim 0.8.*
* zig 0.10.* (compile time)
* haolian9/infra.nvim

## installation
* `zig build -Drelease-safe`

## usage
* `.setup('/run/user/1000/redis.sock')` or `.setup('127.0.0.1', 6379)`
* `.auto()` # register autocmd to record visited files int redis
* `.oldfiles()` # just another `:oldfiles`
* for more uses please have a look at `lua/{init,RedisClient}.lua`

## notes
* libredisclient.so will block the lua process during communicating with redis,
  which may hurt nvim's responsiveness.
* it's an alternative to nvim's builtin oldfiles, user may consider having `'0` in &shada.
* the round-trip time of PING is about 0.2ms

## todo

maybe it's should to put the network i/o of redis into a dedicated thread
* pro:
    * not blocks the nvim/lua process
* con:
    * need to expose some threading sync primitives
    * much complicated code
* impl:
    * http://docs.libuv.org/en/v1.x/guide/threads.html
    * http://docs.libuv.org/en/v1.x/threading.html
    * luv.new_work or luv.new_thread
    * uv.uv_mutex_*
