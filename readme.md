
## features
* global MRU/old files
* long-lived redis connection
* storing data in redis
* history size
* programming apis: for fond.nvim
* :oldfiles

## status
* just works
* no new features are planned
* the use of luajit's ffi lib may cause crash nvim

## prerequisites
* redis >= 6.* (okredis)
* nvim 0.8.*
* zig 0.10.* (compile time)
* haolian9/infra.nvim

## installation
* `zig build -Drelease-safe`

## usage
* `.setup('/run/user/1000/redis.sock')` # tcp address (ip:port) is not exposed yet.
* `.auto()` # register autocmd to record visited files and store them in redis
* `.oldfiles()` # just another `:oldfiles`
* for more uses please have a look at `lua/{init,redis_client}.lua`

## notes
* libredisclient.so will block the lua process during communicating with redis,
  which may hurt nvim's responsiveness.
* it's an alternative to nvim's builtin oldfiles feature, user may consider having `'0` in &shada.
* the round-trip time of PING is about 0.2ms
