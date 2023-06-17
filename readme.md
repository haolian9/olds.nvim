an opinionated 'oldfiles' impl for nvim

## features
* global old files
* storing data in redis
* limited history size
* programming apis: for fond.nvim
* :oldfiles

## status
* it just works (tm)
* it is feature-freezed
* it can only connect to redis's unix socket

## prerequisites
* linux
* redis >= 7.*
* nvim 0.9.*

## usage
* `.setup('/run/user/1000/redis.sock')`
* `.auto()` # register autocmd to record visited files int redis
* `.oldfiles()` # equal to `:oldfiles`
* for more uses please have a look at `lua/{init,RedisClient}.lua`
