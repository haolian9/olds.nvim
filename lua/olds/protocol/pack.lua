local ropes = require("string.buffer")

--A client sends the Redis server a RESP Array consisting of only Bulk Strings.
---@param cmd string
---@param ... string|number
---@return string
return function(cmd, ...)
  assert(cmd)

  local nargs = select("#", ...)
  local total = 1 + nargs
  local rope = ropes.new()

  rope:putf("*%d\r\n", total)
  rope:putf("$%d\r\n", #cmd):putf("%s\r\n", cmd)

  for i = 1, nargs do
    local a = select(i, ...)
    if type(a) ~= "string" then a = tostring(a) end
    rope:putf("$%d\r\n", #a):putf("%s\r\n", a)
  end

  return rope:get()
end
