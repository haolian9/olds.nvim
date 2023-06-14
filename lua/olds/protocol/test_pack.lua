local pack = require("olds.protocol.pack")

assert(pack("ping") == "*1\r\n$4\r\nping\r\n")
assert(pack("keys", "*") == "*2\r\n$4\r\nkeys\r\n$1\r\n*\r\n")
