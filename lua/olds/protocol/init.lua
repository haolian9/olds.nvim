--ref: https://github.com/redis/redis-specifications/blob/master/protocol/RESP2.md

local oop = require("infra.oop")

return {
  pack = oop.proxy("olds.protocol.pack"),
  unpack = oop.proxy("olds.protocol.unpack"),
  Stash = oop.proxy("olds.protocol.Stash"),
}
