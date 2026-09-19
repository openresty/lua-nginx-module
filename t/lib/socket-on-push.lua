local _M = {}
local port = tonumber(os.getenv("TEST_NGINX_PUSH_PORT"))

local function socket()
    local sock = ngx.socket.tcp()
    sock:settimeout(4000)
    return sock
end

function _M.control()
    local sock = socket()
    assert(sock:connect("127.0.0.1", port, { pool = "push-control" }))
    assert(sock:send("CONTROL\n"))
    return sock
end

function _M.command(control, command, name, data)
    if data then
        local hex = data:gsub(".", function(c)
            return string.format("%02x", string.byte(c))
        end)
        command = command .. " " .. name .. " " .. hex
    else
        command = command .. " " .. name
    end
    assert(control:send(command .. "\n"))
    local reply = assert(control:receive())
    assert(reply == "OK", reply)
end

function _M.connect(name, callback)
    local sock = socket()
    assert(sock:connect("127.0.0.1", port, {
        pool = name, pool_size = 1, on_push = callback,
    }))
    if sock:getreusedtimes() == 0 then
        assert(sock:send("OPEN " .. name .. "\n"))
        assert(sock:receive() == "READY")
    end
    return sock
end

function _M.wait(predicate)
    local deadline = ngx.now() + 3
    while not predicate() do
        assert(ngx.now() < deadline, "push callback timed out")
        ngx.sleep(0.001)
    end
end

function _M.reuse(name, control, callback)
    local sock = _M.connect(name, callback)
    ngx.say("reused: ", sock:getreusedtimes())
    -- Verify that it is still the server's original connection, in both
    -- directions, rather than merely trusting the pool's reuse counter.
    assert(sock:send("CHECK\r\n"))
    _M.command(control, "EXPECT", name, "CHECK\r\n")
    _M.command(control, "SEND", name, "ALIVE\r\n")
    assert(sock:receive() == "ALIVE")
    return sock
end

return _M
