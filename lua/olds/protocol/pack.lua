--A client sends the Redis server a RESP Array consisting of only Bulk Strings.
---@param cmd string
---@param ... string|number
---@return string
return function(cmd, ...)
  assert(cmd)
  local parts
  do
    local nargs = select("#", ...)
    local total = 1 + nargs
    parts = { "*" .. total, "$" .. #cmd, cmd }
    for i = 1, nargs do
      local a = select(i, ...)
      if type(a) ~= "string" then a = tostring(a) end
      table.insert(parts, "$" .. #a)
      table.insert(parts, a)
    end
    table.insert(parts, "")
  end
  return table.concat(parts, "\r\n")
end
