an opinionated 'oldfiles' impl for nvim

## features
* limited history among nvim instances
* record = path + line + col
* redis as the persistent target

## status
* it just works (tm)
* it can only connect to redis's unix socket right now

## prerequisites
* linux
* redis >= 7.*
* nvim 0.9.*

## usage
* `.setup('/run/user/1000/redis.sock')`
* `.init()` for automatically recording
* `.oldfiles()`, `.dump()`, `.reset()`, `.prune()`
