# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    if (!defined $ENV{LD_PRELOAD}) {
        $ENV{LD_PRELOAD} = '';
    }

    if ($ENV{LD_PRELOAD} !~ /\bmockeagain\.so\b/) {
        $ENV{LD_PRELOAD} = "mockeagain.so $ENV{LD_PRELOAD}";
    }

    if ($ENV{MOCKEAGAIN} eq 'r') {
        $ENV{MOCKEAGAIN} = 'rw';

    } else {
        $ENV{MOCKEAGAIN} = 'w';
    }

    $ENV{TEST_NGINX_EVENT_TYPE} = 'poll';
    delete($ENV{TEST_NGINX_USE_HTTP2});
    $ENV{MOCKEAGAIN_WRITE_TIMEOUT_PATTERN} = 'slowdata';
}

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();
run_tests();

__DATA__

=== TEST 1: read timeout
--- config
    server_tokens off;
    location /t {
        resolver $TEST_NGINX_RESOLVER ipv6=off;
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeouts(150, 150, 2)  -- 2ms read timeout

            local port = ngx.var.server_port
            local ok, err = sock:connect("localhost", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET /foo HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            sock:close()
        }
    }

    location /foo {
        content_by_lua_block {
            ngx.sleep(0.01) -- 10 ms
            ngx.say("foo")
        }
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body_like
failed to receive a line: timeout \[\]
--- error_log eval
qr/lua tcp socket read timed out, upstream: localhost:\d+\(127.0.0.1\)/



=== TEST 2: send timeout
--- config
    server_tokens off;
    location /t {
        resolver $TEST_NGINX_RESOLVER ipv6=off;
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeouts(500, 500, 500)  -- 500ms timeout

            local port = ngx.var.server_port
            local ok, err = sock:connect("localhost", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local data = "slowdata" -- slow data
            local num = 10

            local req = "POST /foo HTTP/1.0\r\nHost: localhost\r\nContent-Length: "
                        .. #data * num .. "\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            for i = 1, num do
                local bytes, err = sock:send(data)
                if not bytes then
                    ngx.say("failed to send body: ", err)
                    return
                end
            end

            while true do
                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                    break
                end
            end

            sock:close()
        }
    }

    location /foo {
        content_by_lua_block {
            local content_length = ngx.req.get_headers()["Content-Length"]

            local sock = ngx.req.socket()

            sock:settimeouts(500, 500, 500)

            local chunk = 8

            for i = 1, content_length, chunk do
                local data, err = sock:receive(chunk)
                if not data then
                    ngx.say("failed to receive chunk: ", err)
                    return
                end
            end

            ngx.say("got len: ", content_length)
        }
    }

--- request
GET /t
--- response_body
failed to send body: timeout
--- error_log eval
qr/lua tcp socket write timed out, upstream: localhost:\d+\(127.0.0.1\)/



=== TEST 3: read timeout
--- config
    server_tokens off;
    location /t {
        resolver $TEST_NGINX_RESOLVER ipv6=off;
        content_by_lua_block {
            local function do_req(uri)
                local sock = ngx.socket.tcp()

                sock:settimeouts(150, 150, 150)  -- 150ms

                local port = ngx.var.server_port
                local ok, err = sock:connect("localhost", port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                local req = "GET " .. uri .. " HTTP/1.1\r\nHost: localhost\r\n\r\n"

                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send request: ", err)
                    return
                end

                local reader = sock:receiveuntil("\r\n0\r\n\r\n")
                local data, err = reader()

                if not data then
                    ngx.say("failed to receive response body: ", err)
                    return
                end

                ngx.say("received response of ", #data, " bytes")

                local ok, err = sock:setkeepalive()
                if not ok then
                    ngx.say("failed to set reusable: ", err)

                    sock:setkeepalive()
                end
            end

            do_req("/foo")
            do_req("/bar")
        }
    }

    location /foo {
        content_by_lua_block {
            ngx.say("foo")
            ngx.flush()
            ngx.say("end")
        }
        more_clear_headers Date;
    }

    location /bar {
        content_by_lua_block {
            ngx.sleep(0.2)
            ngx.say("bar")
            ngx.flush()
            ngx.say("end")
        }
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body_like
received response of 128 bytes
failed to receive response body: timeout
--- error_log eval
qr/lua tcp socket read timed out, upstream: localhost:\d+\(127.0.0.1\)/



=== TEST 4: send timeout keepalive
--- config
    server_tokens off;
    location /t {
        resolver $TEST_NGINX_RESOLVER ipv6=off;
        content_by_lua_block {
            local function do_req(uri, data)
                local sock = ngx.socket.tcp()

                sock:settimeouts(500, 500, 500)  -- 500ms timeout

                local port = ngx.var.server_port
                local ok, err = sock:connect("localhost", port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                local num = 10

                local req = "POST " .. uri .." HTTP/1.1\r\nHost: localhost\r\nContent-Length: "
                            .. #data * num .. "\r\nConnection: close\r\n\r\n"

                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send request: ", err)
                    return
                end

                for i = 1, num do
                    local bytes, err = sock:send(data)
                    if not bytes then
                        ngx.say("failed to send body: ", err)
                        return
                    end
                end

                local reader = sock:receiveuntil("\r\n0\r\n\r\n")
                local data, err = reader()

                if not data then
                    ngx.say("failed to receive response body: ", err)
                    return
                end

                ngx.say("received response of ", #data, " bytes")

                local ok, err = sock:setkeepalive()
                if not ok then
                    ngx.say("failed to set reusable: ", err)

                    sock:setkeepalive()
                end
            end

            do_req("/foo", "quicdata")
            do_req("/foo", "slowdata")
        }
    }

    location /foo {
        content_by_lua_block {
            ngx.say("hello world")
        }
    }

--- request
GET /t
--- response_body
received response of 159 bytes
failed to send body: timeout
--- error_log eval
qr/lua tcp socket write timed out, upstream: localhost:\d+\(127.0.0.1\)/
