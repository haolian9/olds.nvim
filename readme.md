an opinionated 'oldfiles' impl

## features
* limited history among nvim instances
* record = path + line + col
* redis as the persistent target

## status
* just works

## prerequisites
* linux
* redis >= 7.*
* nvim 0.9.*
* haolian9/infra.nvim

## usage
* `require'infra.G'('olds').create_client = function() return require('olds.RedisClient').connect_unix('/run/user/1000/redis.sock') end`
* `.init()` for automatically recording
* `.oldfiles()`, `.dump()`, `.reset()`, `.prune()`
