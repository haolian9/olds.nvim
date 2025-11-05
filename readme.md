an opinionated 'oldfiles' impl

## features
* fixed-length history among nvim instances
* record = path + line + col
* redis as the persistent target

## status
* just works

## prerequisites
* linux
* valkey 8.1.* or redis 7.*
* nvim 0.10.*
* haolian9/infra.nvim

## usage

preflight:
```
require'infra.G'('olds').create_client = function()
  return require('olds.RedisClient').connect_unix('/run/user/1000/redis.sock')
end
```

apis:
* start_recording, stop_recording
* show_history, reset_history, prune_history
* dump
* ping
