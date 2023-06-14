local strlib = require("infra.strlib")

---@class olds.Slice
---@field data string
---@field start number
---@field len number
-- todo: more bound methods to slice

local exactor = {}
do
  ---@param slice olds.Slice
  ---@return olds.Slice
  function exactor.bulk_string(slice)
    assert(string.sub(slice.data, slice.start, slice.start) == "$")
    local len_start = slice.start + 1 -- plus `$`
    local len_stop = assert(strlib.find(slice.data, "\r\n", len_start), "missing end of bulk string len") - 1
    local len = assert(tonumber(string.sub(slice.data, len_start, len_stop)))
    if len == -1 then error("unsupported nil string") end
    local str_start = len_stop + 2 + 1 -- plus `\r\n`
    return { data = slice.data, start = str_start, len = len }
  end

  ---@param slice olds.Slice
  ---@return olds.Slice
  function exactor.error_(slice)
    assert(string.sub(slice.data, slice.start, slice.start) == "-")
    local err_start = slice.start + 1
    local err_stop = assert(strlib.find(slice.data, "\r\n", err_start), "missing end of error") - 1
    return { data = slice.data, start = err_start, len = err_stop - err_start + 1 }
  end

  function exactor.simple_string(slice)
    assert(string.sub(slice.data, slice.start, slice.start) == "+")
    local str_start = slice.start + 1
    local str_stop = assert(strlib.find(slice.data, "\r\n", str_start), "missing end of simple string") - 1
    return { data = slice.data, start = str_start, len = str_stop - str_start + 1 }
  end
  function exactor.integer(slice)
    assert(string.sub(slice.data, slice.start, slice.start) == ":")
    local int_start = slice.start + 1
    local int_stop = assert(strlib.find(slice.data, "\r\n", int_start), "missing end of simple string") - 1
    return { data = slice.data, start = int_start, len = int_stop - int_start + 1 }
  end
end

local resolver = {}
do
  function resolver.error_(slice)
    local err_slice = exactor.error_(slice)
    return string.sub(err_slice.data, err_slice.start, err_slice.start + err_slice.len - 1)
  end

  function resolver.simple_string(slice)
    local str_slice = exactor.simple_string(slice)
    return string.sub(str_slice.data, str_slice.start, str_slice.start + str_slice.len - 1)
  end

  function resolver.integer(slice)
    local int_slice = exactor.integer(slice)
    return string.sub(int_slice.data, int_slice.start, int_slice.start + int_slice.len - 1)
  end

  ---@param slice olds.Slice
  ---@return string
  function resolver.bulk_string(slice)
    local subslice = exactor.bulk_string(slice)
    return string.sub(subslice.data, subslice.start, subslice.start + subslice.len - 1)
  end

  ---@param slice olds.Slice
  ---@return any[]
  function resolver.array(slice)
    assert(string.sub(slice.data, slice.start, slice.start) == "*", "not a array")

    local mem_len, mem_start
    do
      local len_start = slice.start + 1
      local len_stop = assert(strlib.find(slice.data, "\r\n", len_start), "missing end of len") - 1
      local len = assert(tonumber(string.sub(slice.data, len_start, len_stop)))
      if len == 0 then return {} end
      if len == -1 then error("unsupported nil list") end
      mem_len = len
      mem_start = len_stop + 2 + 1 -- plus `\r\n`
    end

    local list = {}
    local offset = mem_start
    while offset < slice.len do
      local byte0 = string.sub(slice.data, offset, offset)
      local exact_fn
      if byte0 == "$" then
        exact_fn = exactor.bulk_string
      elseif byte0 == "+" then
        exact_fn = exactor.simple_string
      elseif byte0 == ":" then
        exact_fn = exactor.integer
      else
        error("unsupported member type of array: " .. byte0)
      end
      assert(exact_fn)
      local subslice = exact_fn({ data = slice.data, start = offset, len = slice.len - offset + 1 })
      table.insert(list, string.sub(subslice.data, subslice.start, subslice.start + subslice.len - 1))
      offset = subslice.start + subslice.len + 2 -- plus `\r\n`
    end
    assert(#list == mem_len, "data over/underflowed")
    return list
  end
end

--assume data is just one reply, no more no less
---@param data string
---@return any,string? @data,error
return function(data)
  assert(data and #data > 3)
  assert(string.sub(data, -2) == "\r\n", "incomplete reply")
  local slice = { data = data, start = 1, len = #data }

  -- todo: ensure all the data are consumed
  local byte0 = string.sub(data, 1, 1)
  if byte0 == "+" then
    return resolver.simple_string(slice)
  elseif byte0 == "-" then
    return resolver.error_(slice)
  elseif byte0 == ":" then
    return resolver.integer(slice)
  elseif byte0 == "$" then
    return resolver.bulk_string(slice)
  elseif byte0 == "*" then
    return resolver.array(slice)
  else
    error("unreachable")
  end
end
