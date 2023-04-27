
## features
* global old files
* storing data in redis
* limited history size
* programming apis: for fond.nvim
* :oldfiles

## status
* it just works (tm)
* it crashes often

## prerequisites
* linux
* redis >= 7.*
* nvim 0.9.*

## usage
* `.setup('/run/user/1000/redis.sock')` or `.setup('127.0.0.1', 6379)`
* `.auto()` # register autocmd to record visited files int redis
* `.oldfiles()` # just another `:oldfiles`
* for more uses please have a look at `lua/{init,RedisClient}.lua`

## notes
`olds.protocol.unpack` does not support parsing multiple chunked data, it expects the data
passed in be a single reply, no more no less. this can cause problems when the
payload is bigger than PIPE_BUF.

## todo
* make olds.protocol.unpack able to process stream data:
    * .unpack(reader) vs. .feed(data)
