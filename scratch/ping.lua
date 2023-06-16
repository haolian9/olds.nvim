local RedisClient = require("olds.RedisClient")

local client = RedisClient.connect_unix("/run/user/1000/redis.sock")

local reply = client:send("ping")
print(reply.data, reply.err)
