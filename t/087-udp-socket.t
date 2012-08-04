# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * (3 * blocks() + 4);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

log_level 'warn';

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", port)
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
--- response_body eval
"connected\nreceived 12 bytes: \x{00}\x{01}\x{00}\x{00}\x{00}\x{01}\x{00}\x{00}OK\x{0d}\x{0a}"
--- no_error_log
[error]
--- log_level: debug
--- error_log
lua udp socket receive buffer size: 8192



=== TEST 2: multiple parallel queries
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", port)
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

            req = "\\0\\2\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
            ok, err = udp:send(req)
            if not ok then
                ngx.say("failed to send: ", err)
                return
            end

            ngx.sleep(0.05)

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("1: received ", #data, " bytes: ", data)

            data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("2: received ", #data, " bytes: ", data)
        ';
    }
--- request
GET /t
--- response_body_like eval
"^connected\n"
."1: received 12 bytes: "
."\x{00}[\1\2]\x{00}\x{00}\x{00}\x{01}\x{00}\x{00}OK\x{0d}\x{0a}"
."2: received 12 bytes: "
."\x{00}[\1\2]\x{00}\x{00}\x{00}\x{01}\x{00}\x{00}OK\x{0d}\x{0a}\$"
--- no_error_log
[error]



=== TEST 3: access a TCP interface
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_CLIENT_PORT;
        #set $port 1234;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", port)
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
--- error_log
recv() failed (111: Connection refused)



=== TEST 4: access conflicts of connect() on shared udp objects
--- http_config
    lua_package_path '$prefix/html/?.lua;;';
--- config
    server_tokens off;
    location /main {
        content_by_lua '
            local reqs = {}
            for i = 1, 170 do
                table.insert(reqs, {"/t"})
            end
            local resps = {ngx.location.capture_multi(reqs)}
            for i = 1, 170 do
                ngx.say(resps[i].status)
            end
        ';
    }

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local port = ngx.var.port
            local foo = require "foo"
            local udp = foo.get_udp()

            udp:settimeout(100) -- 100 ms

            local ok, err = udp:setpeername("127.0.0.1", port)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(500)
            end

            ngx.say("connected")

            local data, err = udp:receive()
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- user_files
>>> foo.lua
module("foo", package.seeall)

local udp

function get_udp()
    if not udp then
        udp = ngx.socket.udp()
    end

    return udp
end
--- request
GET /main
--- response_body_like: \b500\b
--- error_log
failed to connect: socket busy



=== TEST 5: access conflicts of receive() on shared udp objects
--- http_config
    lua_package_path '$prefix/html/?.lua;;';
--- config
    server_tokens off;
    location /main {
        content_by_lua '
            local reqs = {}
            for i = 1, 170 do
                table.insert(reqs, {"/t"})
            end
            local resps = {ngx.location.capture_multi(reqs)}
            for i = 1, 170 do
                ngx.say(resps[i].status)
            end
        ';
    }

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local port = ngx.var.port
            local foo = require "foo"
            local udp = foo.get_udp(port)

            local data, err = udp:receive()
            if not data then
                ngx.log(ngx.ERR, "failed to receive data: ", err)
                return ngx.exit(500)
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- user_files
>>> foo.lua
module("foo", package.seeall)

local udp

function get_udp(port)
    if not udp then
        udp = ngx.socket.udp()

        udp:settimeout(100) -- 100ms

        local ok, err = udp:setpeername("127.0.0.1", port)
        if not ok then
            ngx.log(ngx.ERR, "failed to connect: ", err)
            return ngx.exit(500)
        end
    end

    return udp
end
--- request
GET /main
--- response_body_like: \b500\b
--- error_log
failed to receive data: socket busy



=== TEST 6: connect again immediately
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local sock = ngx.socket.udp()
            local port = ngx.var.port

            local ok, err = sock:setpeername("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            ok, err = sock:setpeername("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected again: ", ok)

            local req = "\\0\\1\\0\\0\\0\\1\\0\\0flush_all\\r\\n"
            local ok, err = sock:send(req)
            if not ok then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", ok)

            local line, err = sock:receive()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive: ", err)
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
"connected: 1
connected again: 1
request sent: 1
received: \0\1\0\0\0\1\0\0OK\r\n
close: 1 nil
"
--- no_error_log
[error]
--- error_log eval
["lua reuse socket upstream", "lua udp socket reconnect without shutting down"]
--- log_level: debug



=== TEST 7: recv timeout
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.udp()
            sock:settimeout(100) -- 100 ms

            local ok, err = sock:setpeername("127.0.0.1", port)
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
lua udp socket read timed out



=== TEST 8: with an explicit receive buffer size argument
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #set $port 1234;

        content_by_lua '
            local socket = ngx.socket
            -- local socket = require "socket"

            local udp = socket.udp()

            local port = ngx.var.port
            udp:settimeout(1000) -- 1 sec

            local ok, err = udp:setpeername("127.0.0.1", port)
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

            local data, err = udp:receive(1400)
            if not data then
                ngx.say("failed to receive data: ", err)
                return
            end
            ngx.print("received ", #data, " bytes: ", data)
        ';
    }
--- request
GET /t
--- response_body eval
"connected\nreceived 12 bytes: \x{00}\x{01}\x{00}\x{00}\x{00}\x{01}\x{00}\x{00}OK\x{0d}\x{0a}"
--- no_error_log
[error]
--- log_level: debug
--- error_log
lua udp socket receive buffer size: 1400



=== TEST 9: read timeout and resend
--- config
    location = /t {
        content_by_lua '
            local udp = ngx.socket.udp()
            udp:settimeout(30)
            local ok, err = udp:setpeername("127.0.0.1", 19232)
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
--- udp_reply_delay: 45ms
--- request
GET /t
--- response_body
received: hello world
--- error_log
lua udp socket read timed out

