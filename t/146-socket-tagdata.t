# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4 + 2 - 2 - 2) ;

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
["connected: 1, reused: 0
set tag data not found
",
"connected: 1, reused: 1
set tag data a
"]



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
