local co = coroutine

local function await_raw(fn, ...)
  local thread = fn(...)
  while true do
    local _, have_one, data, err = assert(co.resume(thread))
    if have_one then return data, err end
    co.yield(false, data)
  end
end

local function await_join(fn, ...) return table.concat(await_raw(fn, ...), "") end

--possible yield value forms
--* false, nil, nil
--* true, data, nil
--* true, nil, error
---@param stash olds.protocol.Stash
---@return thread @yield(): (have_one: bool, data?: str|int|[str], err?: str)
return function(stash)
  return co.create(function()
    while true do
      local byte0 = await_join(stash.peekn, stash, 1)
      if byte0 == "+" then
        local msg = await_join(stash.popuntil, stash, "\r\n")
        co.yield(true, string.sub(msg, 2, -3))
      elseif byte0 == "-" then
        local msg = await_join(stash.popuntil, stash, "\r\n")
        co.yield(true, nil, string.sub(msg, 2, -3))
      elseif byte0 == ":" then
        local msg = await_join(stash.popuntil, stash, "\r\n")
        local int = assert(tonumber(string.sub(msg, 2, -3)))
        co.yield(true, int)
      elseif byte0 == "$" then
        local head_part = await_join(stash.popuntil, stash, "\r\n")
        local len = assert(tonumber(string.sub(head_part, 2, -3)))
        if len >= 0 then
          local str_part = await_join(stash.popn, stash, len + 2)
          co.yield(true, string.sub(str_part, 1, -3))
        elseif len == -1 then
          co.yield(true, nil)
        else
          error("unreachable: len < -1")
        end
      elseif byte0 == "*" then
        local llen
        do
          local head_part = await_join(stash.popuntil, stash, "\r\n")
          llen = assert(tonumber(string.sub(head_part, 2, -3)))
        end
        local list = {}
        for _ = 1, llen do
          -- assume all elements are bulk string
          local head_part = await_join(stash.popuntil, stash, "\r\n")
          local len = assert(tonumber(string.sub(head_part, 2, -3)))
          if len >= 0 then
            local str_part = await_join(stash.popn, stash, len + 2)
            table.insert(list, string.sub(str_part, 1, -3))
          elseif len == -1 then
            error("unreachable: a nil element")
          else
            error("unreachable: len < -1")
          end
        end
        co.yield(true, list)
      else
        error("unreachable: unexpected type")
      end
    end
  end)
end
