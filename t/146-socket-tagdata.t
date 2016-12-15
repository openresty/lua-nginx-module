# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4 - 2 * 4) ;

run_tests();

__DATA__



=== TEST 1: sanity
--- http_config eval
--- config
    location /t {
        content_by_lua '
            local port = ngx.var.server_port
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

            local res = sock:gettag("test")
            if not res then
                sock:settag("test", "a")
                ngx.say("set tag data not found")
            else
                ngx.say("set tag data ", res)
            end

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end
        ';
    }
--- request eval
["GET /t", "GET /t"]
--- response_body eval
["connected: 1, reused: 0\nset tag data not found\n",
"connected: 1, reused: 1\nset tag data a\n"]



=== TEST 2: unset tag data
--- no_check_leak
--- config
    location /t {
        content_by_lua '
            local port = ngx.var.server_port
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

            local res = sock:gettag("test")
            if not res then
                sock:settag("test", "a")
                ngx.say("set tag data not found")
            else
                ngx.say("set tag data ", res)
                sock:settag("test", nil)
            end

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end
        ';
    }
--- request eval
["GET /t", "GET /t", "GET /t"]

--- response_body eval
[
"connected: 1, reused: 0
set tag data not found
",
"connected: 1, reused: 1
set tag data a
",
"connected: 1, reused: 2
set tag data not found
"]



=== TEST 3: bound data is gc with socket
# For TEST_NGINX_CHECK_LEAK
--- http_config eval
--- config
    location /t {
        content_by_lua '
            local port = ngx.var.server_port
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

            local res = sock:gettag("test")
            if not res then
                sock:settag("test", string.rep("a",60))
                ngx.say("set tag data not found")
            end

            local ok, err = sock:gettag("test")
            ngx.say("set tag data ", ok)
        ';
    }
--- request
GET /t

--- response_body
connected: 1, reused: 0
set tag data not found
set tag data aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa



=== TEST 4: test bound data is GC when not referenced
# For TEST_NGINX_CHECK_LEAK
--- config
    location /t {
        content_by_lua '
            local port = ngx.var.server_port
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res = sock:gettag("test")
            if not res then
                sock:settag("test", string.rep("a",60))
                res = sock:gettag("test")
            end

            ngx.say("set tag data ", res)

            sock:settag("test", nil)

            local ok, err = sock:gettag("test")
            if not ok then
                ngx.say("removed")
            end

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end
        ';
    }
--- request
GET /t

--- response_body
set tag data aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
removed



=== TEST 5: tag data is ok after Lua's Garbage Collection
# For TEST_NGINX_CHECK_LEAK
--- config
    location /t {
        content_by_lua '
            local port = ngx.var.server_port
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res = sock:gettag("test")
            if not res then
                sock:settag("test", string.rep("a", 10))
                res = sock:gettag("test")
            end

            ngx.say("set tag data ", res)

            collectgarbage();

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = sock:gettag("test")
            if not res then
                ngx.say("removed")
            else
                ngx.say("tag data ", res)
            end

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
set tag data aaaaaaaaaa
tag data aaaaaaaaaa



=== TEST 5: number, string, nil and boolean for value
# For TEST_NGINX_CHECK_LEAK
--- config
    location /t {
        content_by_lua '
            local port = ngx.var.server_port
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local function set_get_tag(key, value)
                ok, err = sock:settag(key, value)
                if not ok then
                    ngx.say("set tag data failed: ", err)
                end

                local res = sock:gettag(key)
                if not res then
                    ngx.say("tag data removed key: ", key)
                else
                    ngx.say("tag data key:", key, " value: ", value, " type: ", type(value))
                end
            end

            set_get_tag("test", 33.33)
            set_get_tag("test", "string")
            set_get_tag("test", nil)
            set_get_tag("test", true)

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
tag data key:test value: 33.33 type: number
tag data key:test value: string type: string
tag data removed key: test
tag data key:test value: true type: boolean



=== TEST 6: number for key
# For TEST_NGINX_CHECK_LEAK
--- config
    location /t {
        content_by_lua '
            local port = ngx.var.server_port
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            sock:settag(22, "value")
        ';
    }
--- request
GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/\[error\] .*bad argument #1 to \'settag\' \(string expected, got number\)/



=== TEST 7: upstream sockets close prematurely
# For TEST_NGINX_CHECK_LEAK
--- config
    location /t {
        content_by_lua '
            local sock = ngx.req.socket()

            local ok, err = sock:settag("key", "value")
            if not ok then
                ngx.log(ngx.ERR, "set tag data fail: ", err)
                return
            end

            local res, err = sock:gettag("key")
            if not res then
                ngx.log(ngx.ERR, "get tag data fail: ", err)
            else
                ngx.log(ngx.ERR, "get tag data succ: ", res)
            end
        ';
    }
--- request eval
"POST /t
hello"
--- error_code: 200
--- error_log eval
[
qr/\[error\] .* get tag data succ: value/,
"lua tcp socket tag data free: "
]



=== TEST 8: upstream sockets close prematurely
# For TEST_NGINX_CHECK_LEAK
--- config
    location /t {
        rewrite_by_lua '
            local port = ngx.var.server_port
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = sock:settag("key", "value")
            if not ok then
                ngx.log(ngx.ERR, "set tag data fail: ", err)
                return
            end

            local ok, err = sock:setkeepalive(10, 3)
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.sleep(1)
        ';

        content_by_lua_block {
            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log eval
[
"lua tcp socket keepalive close handler",
"lua tcp socket tag data free: "
]



=== TEST 9: upstream sockets close
# For TEST_NGINX_CHECK_LEAK
--- config
    location /t {
        content_by_lua '
            local port = ngx.var.server_port
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ok, err = sock:settag("test", "a")
            if not ok then
                ngx.say("failed to set tag: ", err)
                return
            end

            ok, err = sock:close()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.say("done")
        ';
    }
--- request
GET /t
--- response_body
done
--- error_log eval
[
"lua finalize socket",
"lua tcp socket tag data free: "
]



=== TEST 10: upstream sockets destroy
# For TEST_NGINX_CHECK_LEAK
--- config
    location /t {
        content_by_lua '
            local port = ngx.var.server_port
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ok, err = sock:settag("test", "a")
            if not ok then
                ngx.say("failed to set tag: ", err)
                return
            end

            ngx.say("done")
        ';
    }
--- request
GET /t
--- response_body
done
--- error_log eval
[
"lua finalize socket",
"lua tcp socket tag data free: "
]

