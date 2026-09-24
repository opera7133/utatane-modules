-- Original fixture for utatane-modules. No real ghost assets are included.
local root
local count = 0
return {
  load = function(path)
    root = path
    local file = io.open(root .. 'count.txt', 'r')
    if file then count = tonumber(file:read('*a')); file:close() end
    return true
  end,
  request = function(request)
    if request:find('ID: Break', 1, true) then error('intentional fixture failure') end
    count = count + 1
    return 'SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: こんにちは' .. count .. '\r\n\r\n'
  end,
  unload = function()
    local file = assert(io.open(root .. 'count.txt', 'w'))
    file:write(tostring(count)); file:close()
    return true
  end
}
