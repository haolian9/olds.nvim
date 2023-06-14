local strlib = require("infra.strlib")

local unpack = require("olds.protocol.unpack")

do
  local data, err = unpack("-ERR unknown command 'hello'\r\n")
  assert(data == nil and err == "ERR unknown command 'hello'")
end

assert(unpack("+OK\r\n") == "OK")
assert(unpack(":99\r\n") == "99")
assert(unpack(":-1\r\n") == "-1")
assert(unpack("$5\r\nhello\r\n") == "hello")
assert(unpack("$0\r\n\r\n") == "")

do
  local ok, err = pcall(unpack, "$-1\r\n")
  assert(not ok and strlib.find(err, "unsupported nil string"))
end
do
  local resolved = unpack("*2\r\n$5\r\nhello\r\n$5\r\nworld\r\n")
  assert(#resolved == 2 and resolved[1] == "hello" and resolved[2] == "world")
end
do
  local resolved = unpack("*3\r\n:1\r\n:2\r\n:3\r\n")
  assert(#resolved == 3 and resolved[1] == "1" and resolved[2] == "2" and resolved[3] == "3")
end
do
  local resolved = unpack("*4\r\n:1\r\n:2\r\n$5\r\nhello\r\n+world\r\n")
  assert(#resolved == 4 and resolved[1] == "1" and resolved[2] == "2" and resolved[3] == "hello" and resolved[4] == "world")
end
