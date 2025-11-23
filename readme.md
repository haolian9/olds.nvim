an opinionated 'oldfiles' impl

## features
* store data in redis
* fixed-length history among nvim instances
* record = '{path}:{line}:{col}'

## status
* just works

## prerequisites
* linux
* valkey 8.1.* or redis 7.*
* nvim 0.11.*
* haolian9/infra.nvim

## usage
```
do
  ---@type olds.G
  local g = G("olds")
  g.create_client = function() return require("olds.RedisClient").connect_unix("/run/user/1000/redis.sock") end

  local olds = require("olds")
  olds.start_recording()
end
```

## credits
* [mru.lua](https://github.com/ii14/dotfiles/blob/master/.config/nvim/lua/mru.lua) by ii14. let me know what autocmds should be listened.
