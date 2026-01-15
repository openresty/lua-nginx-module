# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

log_level 'debug';

no_long_string();
#no_diff();
#no_shuffle();
check_accum_error_log();
run_tests();

__DATA__

=== TEST 1: access a TCP interface
test-nginx use the same port for tcp(http) and udp(http3)
so need to change to a port that is not listen by any app.
default port range:
net.ipv4.ip_local_port_range = 32768	60999
choose a port greater than 61000 should be less race.
--- config
    server_tokens off;
    location /t {
        resolver $TEST_NGINX_RESOLVER ipv6=off;
        set $port 65432;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("localhost", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected")

            local req = "\\0\\1\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
            local ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- request
GET /t
--- response_body
connected
failed to receive data: connection refused
--- error_log eval
qr/recv\(\) failed \(\d+: Connection refused\), upstream: localhost:65432\(127.0.0.1\)/



=== TEST 2: recv timeout
--- config
    server_tokens off;
    location /t {
        resolver $TEST_NGINX_RESOLVER ipv6=off;
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.udp()
            sock:settimeout(100) -- 100 ms

            local ok, err = sock:setpeername("localhost", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local line, err = sock:receive()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive: ", err)
            end

            -- ok, err = sock:close()
            -- ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- error_log
lua udp socket read timed out, upstream: localhost:11211(127.0.0.1)



=== TEST 3: read timeout and re-receive
--- config
    location = /t {
        resolver $TEST_NGINX_RESOLVER ipv6=off;
        content_by_lua '
            local udp = ngx.socket.udp()
            udp:settimeout(80)
            local ok, err = udp:setpeername("localhost", 19232)
            if not ok then
                ngx.say("failed to setpeername: ", err)
                return
            end
            local ok, err = udp:send("blah")
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end
            for i = 1, 2 do
                local data, err = udp:receive()
                if err == "timeout" then
                    -- continue
                else
                    if not data then
                        ngx.say("failed to receive: ", err)
                        return
                    end
                    ngx.say("received: ", data)
                    return
                end
            end

            ngx.say("timed out")
        ';
    }
--- udp_listen: 19232
--- udp_reply: hello world
--- udp_reply_delay: 100ms
--- request
GET /t
--- response_body
received: hello world
--- error_log
lua udp socket read timed out, upstream: localhost:19232(127.0.0.1)



=== TEST 4: access a TCP interface
--- config
    server_tokens off;
    location /t {
        resolver $TEST_NGINX_RESOLVER ipv6=off;
        set $port 65432;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("localhost", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected")

            local req = "\\0\\1\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
            local ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- request
GET /t
--- response_body
connected
failed to receive data: connection refused
--- error_log eval
qr/recv\(\) failed \(\d+: Connection refused\), upstream: localhost:65432\(127.0.0.1\)/



=== TEST 5: recv timeout
--- config
    server_tokens off;
    location /t {
        resolver $TEST_NGINX_RESOLVER ipv6=off;
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.udp()
            sock:settimeout(100) -- 100 ms

            local ok, err = sock:setpeername("localhost", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local line, err = sock:receive()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive: ", err)
            end

            -- ok, err = sock:close()
            -- ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- error_log
lua udp socket read timed out, upstream: localhost:11211(127.0.0.1)



=== TEST 6: read timeout and re-receive
--- config
    location = /t {
        resolver $TEST_NGINX_RESOLVER ipv6=off;
        content_by_lua '
            local udp = ngx.socket.udp()
            udp:settimeout(80)
            local ok, err = udp:setpeername("localhost", 19232)
            if not ok then
                ngx.say("failed to setpeername: ", err)
                return
            end
            local ok, err = udp:send("blah")
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end
            for i = 1, 2 do
                local data, err = udp:receive()
                if err == "timeout" then
                    -- continue
                else
                    if not data then
                        ngx.say("failed to receive: ", err)
                        return
                    end
                    ngx.say("received: ", data)
                    return
                end
            end

            ngx.say("timed out")
        ';
    }
--- udp_listen: 19232
--- udp_reply: hello world
--- udp_reply_delay: 100ms
--- request
GET /t
--- response_body
received: hello world
--- error_log
lua udp socket read timed out, upstream: localhost:19232(127.0.0.1)
