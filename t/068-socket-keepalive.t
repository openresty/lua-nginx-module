# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 35);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

$ENV{LUA_PATH} ||=
    '/usr/local/openresty-debug/lualib/?.lua;/usr/local/openresty/lualib/?.lua;;';

no_long_string();
#no_diff();

#log_level 'warn';
log_level 'debug';

no_shuffle();

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go(port)
            test.go(port)
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local req = "get __nil\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.say("failed to send request: ", err)
        return
    end
    ngx.say("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        ngx.say("received: ", line)

    else
        ngx.say("failed to receive a line: ", err, " [", part, "]")
    end

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body
connected: 1, reused: 0
request sent: 11
received: END
connected: 1, reused: 1
request sent: 11
received: END
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for "]
--- error_log eval
qq{lua tcp socket get keepalive peer: using connection
lua tcp socket keepalive create connection pool for key "127.0.0.1:$ENV{TEST_NGINX_MEMCACHED_PORT}"
}



=== TEST 2: free up the whole connection pool if no active connections
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go(port, true)
            test.go(port, false)
        ';
    }
--- request
GET /t
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port, keepalive)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local req = "get __nil\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.say("failed to send request: ", err)
        return
    end
    ngx.say("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        ngx.say("received: ", line)

    else
        ngx.say("failed to receive a line: ", err, " [", part, "]")
    end

    if keepalive then
        local ok, err = sock:setkeepalive()
        if not ok then
            ngx.say("failed to set reusable: ", err)
        end

    else
        sock:close()
    end
end
--- response_body
connected: 1, reused: 0
request sent: 11
received: END
connected: 1, reused: 1
request sent: 11
received: END
--- no_error_log
[error]
--- error_log eval
["lua tcp socket get keepalive peer: using connection",
"lua tcp socket keepalive: free connection pool for "]



=== TEST 3: upstream sockets close prematurely
--- no_http3
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
   server_tokens off;
   keepalive_timeout 100ms;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, err = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for "]
--- timeout: 3



=== TEST 4: http keepalive
--- quic_max_idle_timeout: 1.2
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
   server_tokens off;
   location /t {
        keepalive_timeout 60s;

        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, err = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log eval
["[error]",
"lua tcp socket keepalive close handler: fd:",
"lua tcp socket keepalive: free connection pool for "]
--- timeout: 4



=== TEST 5: lua_socket_keepalive_timeout
--- quic_max_idle_timeout: 1.2
--- config
   server_tokens off;
   location /t {
       keepalive_timeout 60s;
       lua_socket_keepalive_timeout 100ms;

        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket keepalive timeout: 100 ms",
qr/lua tcp socket connection pool size: 30\b/]
--- timeout: 4



=== TEST 6: lua_socket_pool_size
--- quic_max_idle_timeout: 1.2
--- config
   server_tokens off;
   location /t {
       keepalive_timeout 60s;
       lua_socket_keepalive_timeout 100ms;
       lua_socket_pool_size 1;

        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket keepalive timeout: 100 ms",
qr/lua tcp socket connection pool size: 1\b/]
--- timeout: 4



=== TEST 7: "lua_socket_keepalive_timeout 0" means unlimited
--- quic_max_idle_timeout: 1.2
--- config
   server_tokens off;
   location /t {
       keepalive_timeout 60s;
       lua_socket_keepalive_timeout 0;

        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive timeout: unlimited",
qr/lua tcp socket connection pool size: 30\b/]
--- timeout: 4



=== TEST 8: setkeepalive(timeout) overrides lua_socket_keepalive_timeout
--- quic_max_idle_timeout: 1.2
--- config
   server_tokens off;
   location /t {
        keepalive_timeout 60s;
        lua_socket_keepalive_timeout 60s;

        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive(123)
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket keepalive timeout: 123 ms",
qr/lua tcp socket connection pool size: 30\b/]
--- timeout: 4



=== TEST 9: sock:setkeepalive(timeout, size) overrides lua_socket_pool_size
--- quic_max_idle_timeout: 1.2
--- config
   server_tokens off;
   location /t {
       keepalive_timeout 60s;
       lua_socket_keepalive_timeout 100ms;
       lua_socket_pool_size 100;

        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive(101, 25)
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket keepalive timeout: 101 ms",
qr/lua tcp socket connection pool size: 25\b/]
--- timeout: 4



=== TEST 10: setkeepalive() 'pool_size' should be greater than zero
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua_block {
            local sock, err = ngx.socket.connect("127.0.0.1", ngx.var.port)
            if not sock then
                ngx.say(err)
                return
            end

            local ok, err = pcall(sock.setkeepalive, sock, 0, 0)
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say(ok)
        }
    }
--- request
GET /t
--- response_body
bad argument #3 to '?' (bad "pool_size" option value: 0)
--- no_error_log
[error]



=== TEST 11: sock:keepalive_timeout(0) means unlimited
--- quic_max_idle_timeout: 1.2
--- config
   server_tokens off;
   location /t {
       keepalive_timeout 60s;
       lua_socket_keepalive_timeout 1000ms;

        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive(0)
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive timeout: unlimited",
qr/lua tcp socket connection pool size: 30\b/]
--- timeout: 4



=== TEST 12: sanity (uds)
--- http_config eval
"
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
    server {
        listen unix:$::HtmlDir/nginx.sock;
        default_type 'text/plain';

        server_tokens off;
        location /foo {
            echo foo;
            more_clear_headers Date;
        }
    }
"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local path = "$TEST_NGINX_HTML_DIR/nginx.sock";
            local port = ngx.var.port
            test.go(path, port)
            test.go(path, port)
        ';
    }
--- request
GET /t
--- user_files
>>> test.lua
module("test", package.seeall)

function go(path, port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("unix:" .. path)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local req = "GET /foo HTTP/1.1\r\nHost: localhost\r\nConnection: keepalive\r\n\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.say("failed to send request: ", err)
        return
    end
    ngx.say("request sent: ", bytes)

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
    end
end
--- response_body
connected: 1, reused: 0
request sent: 61
received response of 119 bytes
connected: 1, reused: 1
request sent: 61
received response of 119 bytes
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for "]
--- error_log eval
["lua tcp socket get keepalive peer: using connection",
'lua tcp socket keepalive create connection pool for key "unix:']



=== TEST 13: github issue #108: ngx.location.capture + redis.set_keepalive
--- http_config eval
    qq{
        lua_package_path "$::HtmlDir/?.lua;;";
    }
--- config
    location /t {
        default_type text/html;
        set $port $TEST_NGINX_MEMCACHED_PORT;
        #lua_code_cache off;
        lua_need_request_body on;
        content_by_lua_file html/t.lua;
    }

    location /anyurl {
        internal;
        proxy_pass http://127.0.0.1:$server_port/dummy;
    }

    location = /dummy {
        echo dummy;
    }
--- user_files
>>> t.lua
local sock, err = ngx.socket.connect("127.0.0.1", ngx.var.port)
if not sock then ngx.say(err) return end
sock:send("get __nil\r\n")
sock:receive()
sock:setkeepalive()

sock, err = ngx.socket.connect("127.0.0.1", ngx.var.port)
if not sock then ngx.say(err) return end
local res = ngx.location.capture("/anyurl") --3

ngx.say("ok")
--- request
    GET /t
--- response_body
ok
--- error_log
lua tcp socket get keepalive peer: using connection
--- no_error_log
[error]
[alert]



=== TEST 14: github issue #110: ngx.exit with HTTP_NOT_FOUND causes worker process to exit
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    error_page 404 /404.html;
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        access_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go(port)
            ngx.exit(404)
        ';
        echo hello;
    }
--- user_files
>>> 404.html
Not found, dear...
>>> test.lua
module("test", package.seeall)

function go(port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect: ", err)
        return
    end

    local req = "get __nil\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.log(ngx.ERR, "failed to send request: ", err)
        return
    end

    local line, err, part = sock:receive()
    if not line then
        ngx.log(ngx.ERR, "failed to receive a line: ", err, " [", part, "]")
        return
    end

    -- local ok, err = sock:setkeepalive()
    -- if not ok then
        -- ngx.log(ngx.ERR, "failed to set reusable: ", err)
        -- return
    -- end
end
--- request
GET /t
--- response_body
Not found, dear...
--- error_code: 404
--- no_error_log
[error]



=== TEST 15: custom pools (different pool for the same host:port) - tcp
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go(port, "A")
            test.go(port, "B")
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port, pool)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port, {pool = pool})
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body
connected: 1, reused: 0
connected: 1, reused: 0
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket get keepalive peer: using connection"
]
--- error_log
lua tcp socket keepalive create connection pool for key "A"
lua tcp socket keepalive create connection pool for key "B"



=== TEST 16: custom pools (same pool for different host:port) - tcp
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go($TEST_NGINX_MEMCACHED_PORT, "foo")
            test.go($TEST_NGINX_SERVER_PORT, "foo")
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port, pool)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port, {pool = pool})
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body
connected: 1, reused: 0
connected: 1, reused: 1
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for ",
]
--- error_log
lua tcp socket keepalive create connection pool for key "foo"
lua tcp socket get keepalive peer: using connection



=== TEST 17: custom pools (different pool for the same host:port) - unix
--- http_config eval
"
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
    server {
        listen unix:$::HtmlDir/nginx.sock;
        default_type 'text/plain';

        server_tokens off;
        location /foo {
            echo foo;
            more_clear_headers Date;
        }
    }
"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local path = "$TEST_NGINX_HTML_DIR/nginx.sock";
            test.go(path, "A")
            test.go(path, "B")
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(path, pool)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("unix:" .. path, {pool = pool})
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body
connected: 1, reused: 0
connected: 1, reused: 0
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket get keepalive peer: using connection"
]
--- error_log
lua tcp socket keepalive create connection pool for key "A"
lua tcp socket keepalive create connection pool for key "B"



=== TEST 18: custom pools (same pool for the same path) - unix
--- http_config eval
"
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
    server {
        listen unix:$::HtmlDir/nginx.sock;
        default_type 'text/plain';

        server_tokens off;
    }
"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local path = "$TEST_NGINX_HTML_DIR/nginx.sock";
            test.go(path, "A")
            test.go(path, "A")
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(path, pool)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("unix:" .. path, {pool = pool})
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body
connected: 1, reused: 0
connected: 1, reused: 1
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for ",
]
--- error_log
lua tcp socket keepalive create connection pool for key "A"
lua tcp socket get keepalive peer: using connection



=== TEST 19: numeric pool option value
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go($TEST_NGINX_MEMCACHED_PORT, 3.14)
            test.go($TEST_NGINX_SERVER_PORT, 3.14)
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port, pool)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port, {pool = pool})
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body
connected: 1, reused: 0
connected: 1, reused: 1
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for ",
]
--- error_log
lua tcp socket keepalive create connection pool for key "3.14"
lua tcp socket get keepalive peer: using connection



=== TEST 20: nil pool option value
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go($TEST_NGINX_MEMCACHED_PORT, nil)
            test.go($TEST_NGINX_SERVER_PORT, nil)
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port, pool)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port, {pool = pool})
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body
connected: 1, reused: 0
connected: 1, reused: 0
--- error_code: 200
--- no_error_log
[error]



=== TEST 21: (bad) table pool option value
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go($TEST_NGINX_MEMCACHED_PORT, {})
            test.go($TEST_NGINX_SERVER_PORT, {})
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port, pool)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port, {pool = pool})
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad argument #3 to 'connect' (bad "pool" option type: table)



=== TEST 22: (bad) boolean pool option value
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go($TEST_NGINX_MEMCACHED_PORT, true)
            test.go($TEST_NGINX_SERVER_PORT, false)
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port, pool)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port, {pool = pool})
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad argument #3 to 'connect' (bad "pool" option type: boolean)



=== TEST 23: clear the redis store
--- no_http2
--- config
    location /t {
        redis2_query flushall;
        redis2_pass 127.0.0.1:$TEST_NGINX_REDIS_PORT;
    }
--- request
    GET /t
--- response_body eval
"+OK\r\n"
--- no_error_log
[error]
[alert]
[warn]



=== TEST 24: bug in send(): clear the chain writer ctx
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
    location /t {
        set $port $TEST_NGINX_REDIS_PORT;
        content_by_lua '
            local test = require "test"
            local port = ngx.var.port
            test.go(port)
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(port)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    local bytes, err = sock:send({})
    if err then
        ngx.say("failed to send empty request: ", err)
        return
    end

    local req = "*2\r\n$3\r\nget\r\n$3\r\ndog\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.say("failed to send request: ", err)
        return
    end

    local line, err, part = sock:receive()
    if line then
        ngx.say("received: ", line)

    else
        ngx.say("failed to receive a line: ", err, " [", part, "]")
    end

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end

    ngx.say("done")
end
--- request
GET /t
--- stap2
global active
M(http-lua-socket-tcp-send-start) {
    active = 1
    printf("send [%s] %d\n", text_str(user_string_n($arg3, $arg4)), $arg4)
}
M(http-lua-socket-tcp-receive-done) {
    printf("receive [%s]\n", text_str(user_string_n($arg3, $arg4)))
}
F(ngx_output_chain) {
    #printf("ctx->in: %s\n", ngx_chain_dump($ctx->in))
    #printf("ctx->busy: %s\n", ngx_chain_dump($ctx->busy))
    printf("output chain: %s\n", ngx_chain_dump($in))
}
F(ngx_linux_sendfile_chain) {
    printf("linux sendfile chain: %s\n", ngx_chain_dump($in))
}
F(ngx_chain_writer) {
    printf("chain writer ctx out: %p\n", $data)
    printf("nginx chain writer: %s\n", ngx_chain_dump($in))
}
F(ngx_http_lua_socket_tcp_setkeepalive) {
    delete active
}
M(http-lua-socket-tcp-setkeepalive-buf-unread) {
    printf("setkeepalive unread: [%s]\n", text_str(user_string_n($arg3, $arg4)))
}
probe syscall.recvfrom {
    if (active && pid() == target()) {
        printf("recvfrom(%s)", argstr)
    }
}
probe syscall.recvfrom.return {
    if (active && pid() == target()) {
        printf(" = %s, data [%s]\n", retstr, text_str(user_string_n($ubuf, $size)))
    }
}
probe syscall.writev {
    if (active && pid() == target()) {
        printf("writev(%s)", ngx_iovec_dump($vec, $vlen))
        /*
        for (i = 0; i < $vlen; i++) {
            printf(" %p [%s]", $vec[i]->iov_base, text_str(user_string_n($vec[i]->iov_base, $vec[i]->iov_len)))
        }
        */
    }
}
probe syscall.writev.return {
    if (active && pid() == target()) {
        printf(" = %s\n", retstr)
    }
}
--- response_body
received: $-1
done
--- no_error_log
[error]



=== TEST 25: setkeepalive() with explicit nil args
--- quic_max_idle_timeout: 1.2
--- config
   server_tokens off;
   location /t {
       lua_socket_keepalive_timeout 100ms;

        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\r\nHost: localhost\r\nConnection: keepalive\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\r\n0\r\n\r\n")
            local data, res = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            local ok, err = sock:setkeepalive(nil, nil)
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ngx.location.capture("/sleep")

            ngx.say("done")
        }
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 61
received response of 156 bytes
done
--- no_error_log
[error]
--- error_log eval
["lua tcp socket keepalive close handler",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket keepalive timeout: 100 ms",
qr/lua tcp socket connection pool size: 30\b/]
--- timeout: 4



=== TEST 26: conn queuing: connect() verifies the options for connection pool
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local function check_opts_for_connect(opts)
                local ok, err = pcall(function()
                    sock:connect("127.0.0.1", ngx.var.port, opts)
                end)
                if not ok then
                    ngx.say(err)
                else
                    ngx.say("ok")
                end
            end

            check_opts_for_connect({pool_size = 'a'})
            check_opts_for_connect({pool_size = 0})
            check_opts_for_connect({backlog = -1})
            check_opts_for_connect({backlog = 0})
        }
    }
--- request
GET /t
--- response_body_like
.+ 'connect' \(bad "pool_size" option type: string\)
.+ 'connect' \(bad "pool_size" option value: 0\)
.+ 'connect' \(bad "backlog" option value: -1\)
ok
--- no_error_log
[error]



=== TEST 27: conn queuing: connect() can specify 'pool_size' which overrides setkeepalive()
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local function go()
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("127.0.0.1", port, {pool_size = 1})
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

                local req = "get __nil\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send request: ", err)
                    return
                end
                ngx.say("request sent: ", bytes)

                local line, err, part = sock:receive()
                if line then
                    ngx.say("received: ", line)
                else
                    ngx.say("failed to receive a line: ", err, " [", part, "]")
                end

                local ok, err = sock:setkeepalive(0, 20)
                if not ok then
                    ngx.say("failed to set reusable: ", err)
                end
            end

            -- reuse ok
            go()
            go()

            local sock1 = ngx.socket.connect("127.0.0.1", port)
            local sock2 = ngx.socket.connect("127.0.0.1", port)
            local ok, err = sock1:setkeepalive(0, 20)
            if not ok then
                ngx.say(err)
            end
            local ok, err = sock2:setkeepalive(0, 20)
            if not ok then
                ngx.say(err)
            end

            -- the pool_size is 1 instead of 20
            sock1 = ngx.socket.connect("127.0.0.1", port)
            sock2 = ngx.socket.connect("127.0.0.1", port)
            ngx.say("reused: ", sock1:getreusedtimes())
            ngx.say("reused: ", sock2:getreusedtimes())
            sock1:setkeepalive(0, 20)
            sock2:setkeepalive(0, 20)
        }
    }
--- request
GET /t
--- response_body
connected: 1, reused: 0
request sent: 11
received: END
connected: 1, reused: 1
request sent: 11
received: END
reused: 1
reused: 0
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket connection pool size: 20"]
--- error_log eval
[qq{lua tcp socket keepalive create connection pool for key "127.0.0.1:$ENV{TEST_NGINX_MEMCACHED_PORT}"},
"lua tcp socket connection pool size: 1",
]



=== TEST 28: conn queuing: connect() can specify 'pool_size' for unix domain socket
--- http_config eval
"
    server {
        listen unix:$::HtmlDir/nginx.sock;
    }
"
--- config
    location /t {
        content_by_lua_block {
            local path = "unix:" .. "$TEST_NGINX_HTML_DIR/nginx.sock";
            local function go()
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect(path, {pool_size = 1})
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

                local ok, err = sock:setkeepalive(0, 20)
                if not ok then
                    ngx.say("failed to set reusable: ", err)
                end
            end

            go()
            go()

            local sock1 = ngx.socket.connect(path)
            local sock2 = ngx.socket.connect(path)
            local ok, err = sock1:setkeepalive(0, 20)
            if not ok then
                ngx.say(err)
            end
            local ok, err = sock2:setkeepalive(0, 20)
            if not ok then
                ngx.say(err)
            end

            -- the pool_size is 1 instead of 20
            sock1 = ngx.socket.connect(path)
            sock2 = ngx.socket.connect(path)
            ngx.say("reused: ", sock1:getreusedtimes())
            ngx.say("reused: ", sock2:getreusedtimes())
            sock1:setkeepalive(0, 20)
            sock2:setkeepalive(0, 20)
        }
    }
--- request
GET /t
--- response_body
connected: 1, reused: 0
connected: 1, reused: 1
reused: 1
reused: 0
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket connection pool size: 20"]
--- error_log eval
["lua tcp socket get keepalive peer: using connection",
'lua tcp socket keepalive create connection pool for key "unix:',
"lua tcp socket connection pool size: 1",
]



=== TEST 29: conn queuing: connect() can specify 'pool_size' for custom pool
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local function go(pool)
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("127.0.0.1", port, {pool = pool, pool_size = 1})
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", pool, ", reused: ", sock:getreusedtimes())

                local ok, err = sock:setkeepalive(0, 20)
                if not ok then
                    ngx.say("failed to set reusable: ", err)
                end
            end

            go('A')
            go('B')
            go('A')
            go('B')

            local sock1 = ngx.socket.connect("127.0.0.1", port, {pool = 'A'})
            local sock2 = ngx.socket.connect("127.0.0.1", port, {pool = 'A'})
            local ok, err = sock1:setkeepalive(0, 20)
            if not ok then
                ngx.say(err)
            end
            local ok, err = sock2:setkeepalive(0, 20)
            if not ok then
                ngx.say(err)
            end

            -- the pool_size is 1 instead of 20
            sock1 = ngx.socket.connect("127.0.0.1", port, {pool = 'A'})
            sock2 = ngx.socket.connect("127.0.0.1", port, {pool = 'A'})
            ngx.say("reused: ", sock1:getreusedtimes())
            ngx.say("reused: ", sock2:getreusedtimes())
            sock1:setkeepalive(0, 20)
            sock2:setkeepalive(0, 20)
        }
    }
--- request
GET /t
--- response_body
connected: A, reused: 0
connected: B, reused: 0
connected: A, reused: 1
connected: B, reused: 1
reused: 1
reused: 0
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket connection pool size: 20"]
--- error_log eval
[qq{lua tcp socket keepalive create connection pool for key "A"},
qq{lua tcp socket keepalive create connection pool for key "B"},
"lua tcp socket connection pool size: 1",
]



=== TEST 30: conn queuing: connect() uses lua_socket_pool_size as default if 'backlog' is given
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        lua_socket_pool_size 1234;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {backlog = 0}
            local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not sock then
                ngx.say(err)
            else
                ngx.say("ok")
            end
        }
    }
--- request
GET /t
--- response_body
ok
--- error_log
lua tcp socket connection pool size: 1234
--- no_error_log
[error]



=== TEST 31: conn queuing: more connect operations than 'backlog' size
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool_size = 2, backlog = 0}
            local sock = ngx.socket.connect("127.0.0.1", port, opts)
            local not_reused_socket, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not not_reused_socket then
                ngx.say(err)
                return
            end
            -- burst
            local ok, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not ok then
                ngx.say(err)
            end

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say(err)
                return
            end

            ok, err = sock:connect("127.0.0.1", port, opts)
            if not ok then
                ngx.say(err)
            end
            ngx.say("reused: ", sock:getreusedtimes())
            -- both queue and pool is full
            ok, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
too many waiting connect operations
reused: 1
too many waiting connect operations
--- no_error_log
[error]



=== TEST 32: conn queuing: once 'pool_size' is reached and pool has 'backlog'
--- quic_max_idle_timeout: 1.2
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool_size = 2, backlog = 2}
            local sock1 = ngx.socket.connect("127.0.0.1", port, opts)

            ngx.timer.at(0, function(premature)
                local sock2, err = ngx.socket.connect("127.0.0.1", port, opts)
                if not sock2 then
                    ngx.log(ngx.ERR, err)
                    return
                end

                ngx.log(ngx.WARN, "start to handle timer")
                ngx.sleep(0.1)
                sock2:close()
                -- resume connect operation
                ngx.log(ngx.WARN, "continue to handle timer")
            end)

            ngx.sleep(0.05)
            ngx.log(ngx.WARN, "start to handle cosocket")
            local sock3, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not sock3 then
                ngx.say(err)
                return
            end
            ngx.log(ngx.WARN, "continue to handle cosocket")

            local req = "get __nil\r\n"
            local bytes, err = sock3:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local line, err, part = sock3:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive a line: ", err, " [", part, "]")
            end

            local ok, err = sock3:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end
            ngx.say("setkeepalive: OK")
        }
    }
--- request
GET /t
--- response_body
request sent: 11
received: END
setkeepalive: OK
--- no_error_log
[error]
--- error_log
lua tcp socket queue connect operation for connection pool "127.0.0.1
--- grep_error_log eval: qr/(start|continue) to handle \w+/
--- grep_error_log_out
start to handle timer
start to handle cosocket
continue to handle timer
continue to handle cosocket



=== TEST 33: conn queuing: do not count failed connect operations
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "test", pool_size = 1, backlog = 0}

            local sock = ngx.socket.tcp()
            sock:settimeouts(100, 3000, 3000)
            local ok, err = sock:connect("127.0.0.2", 12345, opts)
            if not ok then
                ngx.say(err)
            end

            local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not sock then
                ngx.say(err)
            end
            ngx.say("ok")
        }
    }
--- request
GET /t
--- error_log
lua tcp socket connect timed out, upstream: 127.0.0.2:12345(127.0.0.2)
--- response_body
timeout
ok



=== TEST 34: conn queuing: connect until backlog is reached
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool_size = 1, backlog = 1}
            local sock1 = ngx.socket.connect("127.0.0.1", port, opts)

            ngx.timer.at(0.01, function(premature)
                ngx.log(ngx.WARN, "start to handle timer")
                local sock2, err = ngx.socket.connect("127.0.0.1", port, opts)
                if not sock2 then
                    ngx.log(ngx.ERR, err)
                    return
                end

                ngx.sleep(0.02)
                local ok, err = sock2:close()
                if not ok then
                    ngx.log(ngx.ERR, err)
                end
                ngx.log(ngx.WARN, "continue to handle timer")
            end)

            ngx.sleep(0.02)
            local sock3, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not sock3 then
                ngx.say(err)
            end
            local ok, err = sock1:setkeepalive()
            if not ok then
                ngx.say(err)
                return
            end
            ngx.sleep(0.01) -- run sock2

            ngx.log(ngx.WARN, "start to handle cosocket")
            local sock3, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not sock3 then
                ngx.say(err)
                return
            end
            ngx.log(ngx.WARN, "continue to handle cosocket")

            local ok, err = sock3:setkeepalive()
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
too many waiting connect operations
--- no_error_log
[error]
--- error_log
lua tcp socket queue connect operation for connection pool "127.0.0.1
--- grep_error_log eval: qr/queue connect operation for connection pool|(start|continue) to handle \w+/
--- grep_error_log_out
start to handle timer
queue connect operation for connection pool
start to handle cosocket
queue connect operation for connection pool
continue to handle timer
continue to handle cosocket



=== TEST 35: conn queuing: memory reuse for host in queueing connect operation ctx
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "test", pool_size = 1, backlog = 3}
            local sock = ngx.socket.connect("127.0.0.1", port, opts)

            ngx.timer.at(0.01, function(premature)
                local sock, err = ngx.socket.connect("0.0.0.0", port, opts)
                if not sock then
                    ngx.log(ngx.ERR, err)
                    return
                end

                local ok, err = sock:close()
                if not ok then
                    ngx.log(ngx.ERR, err)
                end
            end)

            ngx.timer.at(0.015, function(premature)
                local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
                if not sock then
                    ngx.log(ngx.ERR, err)
                    return
                end

                local ok, err = sock:close()
                if not ok then
                    ngx.log(ngx.ERR, err)
                end
            end)

            ngx.timer.at(0.02, function(premature)
                local sock, err = ngx.socket.connect("0.0.0.0", port, opts)
                if not sock then
                    ngx.log(ngx.ERR, err)
                    return
                end

                local ok, err = sock:close()
                if not ok then
                    ngx.log(ngx.ERR, err)
                end
            end)

            ngx.sleep(0.03)
            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
--- grep_error_log eval: qr/queue connect operation for connection pool/
--- grep_error_log_out
queue connect operation for connection pool
queue connect operation for connection pool
queue connect operation for connection pool



=== TEST 36: conn queuing: connect() returns error after connect operation resumed
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "test", pool_size = 1, backlog = 1}
            local sock = ngx.socket.connect("127.0.0.1", port, opts)

            ngx.timer.at(0, function(premature)
                local sock, err = ngx.socket.connect("", port, opts)
                if not sock then
                    ngx.log(ngx.WARN, err)
                end
            end)

            ngx.sleep(0.01)
            -- use 'close' to force parsing host instead of reusing conn
            local ok, err = sock:close()
            if not ok then
                ngx.say(err)
                return
            end
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
--- error_log
failed to parse host name
--- grep_error_log eval: qr/queue connect operation for connection pool/
--- grep_error_log_out
queue connect operation for connection pool



=== TEST 37: conn queuing: in uthread
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool_size = 1, backlog = 2}

            local conn_sock = function()
                local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
                if not sock then
                    ngx.say(err)
                    return
                end
                ngx.say("start to handle uthread")

                ngx.sleep(0.01)
                sock:close()
                ngx.say("continue to handle other uthread")
            end

            local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not sock then
                ngx.log(ngx.ERR, err)
                return
            end

            local co1 = ngx.thread.spawn(conn_sock)
            local co2 = ngx.thread.spawn(conn_sock)
            local co3 = ngx.thread.spawn(conn_sock)

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.log(ngx.ERR, err)
            end

            ngx.thread.wait(co1)
            ngx.thread.wait(co2)
            ngx.thread.wait(co3)
            ngx.say("all uthreads ok")
        }
    }
--- request
GET /t
--- response_body
too many waiting connect operations
start to handle uthread
continue to handle other uthread
start to handle uthread
continue to handle other uthread
all uthreads ok
--- no_error_log
[error]
--- grep_error_log eval: qr/queue connect operation for connection pool/
--- grep_error_log_out
queue connect operation for connection pool
queue connect operation for connection pool



=== TEST 38: conn queuing: in access_by_lua
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        access_by_lua_block {
            local port = ngx.var.port
            local opts = {pool_size = 1, backlog = 2}

            local conn_sock = function()
                local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
                if not sock then
                    ngx.say(err)
                    return
                end
                ngx.say("start to handle uthread")

                ngx.sleep(0.01)
                sock:close()
                ngx.say("continue to handle other uthread")
            end

            local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not sock then
                ngx.log(ngx.ERR, err)
                return
            end

            local co1 = ngx.thread.spawn(conn_sock)
            local co2 = ngx.thread.spawn(conn_sock)
            local co3 = ngx.thread.spawn(conn_sock)

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.log(ngx.ERR, err)
            end

            ngx.thread.wait(co1)
            ngx.thread.wait(co2)
            ngx.thread.wait(co3)
            ngx.say("all uthreads ok")
        }
    }
--- request
GET /t
--- response_body
too many waiting connect operations
start to handle uthread
continue to handle other uthread
start to handle uthread
continue to handle other uthread
all uthreads ok
--- no_error_log
[error]
--- grep_error_log eval: qr/queue connect operation for connection pool/
--- grep_error_log_out
queue connect operation for connection pool
queue connect operation for connection pool



=== TEST 39: conn queuing: in rewrite_by_lua
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        rewrite_by_lua_block {
            local port = ngx.var.port
            local opts = {pool_size = 1, backlog = 2}

            local conn_sock = function()
                local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
                if not sock then
                    ngx.say(err)
                    return
                end
                ngx.say("start to handle uthread")

                ngx.sleep(0.01)
                sock:close()
                ngx.say("continue to handle other uthread")
            end

            local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not sock then
                ngx.log(ngx.ERR, err)
                return
            end

            local co1 = ngx.thread.spawn(conn_sock)
            local co2 = ngx.thread.spawn(conn_sock)
            local co3 = ngx.thread.spawn(conn_sock)

            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.log(ngx.ERR, err)
            end

            ngx.thread.wait(co1)
            ngx.thread.wait(co2)
            ngx.thread.wait(co3)
            ngx.say("all uthreads ok")
        }
    }
--- request
GET /t
--- response_body
too many waiting connect operations
start to handle uthread
continue to handle other uthread
start to handle uthread
continue to handle other uthread
all uthreads ok
--- no_error_log
[error]
--- grep_error_log eval: qr/queue connect operation for connection pool/
--- grep_error_log_out
queue connect operation for connection pool
queue connect operation for connection pool



=== TEST 40: conn queuing: in subrequest
--- config
    set $port $TEST_NGINX_MEMCACHED_PORT;

    location /t {
        content_by_lua_block {
            local port = ngx.var.port
            ngx.timer.at(0, function()
                local opts = {pool_size = 1, backlog = 2}
                local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
                if not sock then
                    ngx.log(ngx.ERR, err)
                    return
                end

                ngx.sleep(0.1)
                local ok, err = sock:setkeepalive()
                if not ok then
                    ngx.log(ngx.ERR, err)
                end
            end)

            ngx.sleep(0.01)
            local res1, res2, res3 = ngx.location.capture_multi{
                {"/conn"}, {"/conn"}, {"/conn"}
            }
            ngx.say(res1.body)
            ngx.say(res2.body)
            ngx.say(res3.body)
        }
    }

    location /conn {
        content_by_lua_block {
            local port = ngx.var.port
            local sock, err = ngx.socket.connect("127.0.0.1", port)
            if not sock then
                ngx.print(err)
                return
            end
            local ok, err = sock:setkeepalive()
            if not ok then
                ngx.print(err)
            else
                ngx.print("ok")
            end
        }
    }
--- request
GET /t
--- response_body
ok
ok
too many waiting connect operations
--- no_error_log
[error]
--- grep_error_log eval: qr/queue connect operation for connection pool/
--- grep_error_log_out
queue connect operation for connection pool
queue connect operation for connection pool



=== TEST 41: conn queuing: timeouts when 'connect_timeout' is reached
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool_size = 1, backlog = 1}
            local sock1 = ngx.socket.connect("127.0.0.1", port, opts)

            local sock2 = ngx.socket.tcp()
            sock2:settimeouts(10, 3000, 3000)
            local ok, err = sock2:connect("127.0.0.1", port, opts)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
timeout
--- error_log eval
"lua tcp socket queued connect timed out, when trying to connect to 127.0.0.1:$ENV{TEST_NGINX_MEMCACHED_PORT}"



=== TEST 42: conn queuing: set timeout via lua_socket_connect_timeout
--- config
    lua_socket_connect_timeout 10ms;
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool_size = 1, backlog = 1}
            local sock1 = ngx.socket.connect("127.0.0.1", port, opts)

            local sock2 = ngx.socket.tcp()
            local ok, err = sock2:connect("127.0.0.1", port, opts)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
timeout
--- error_log eval
"lua tcp socket queued connect timed out, when trying to connect to 127.0.0.1:$ENV{TEST_NGINX_MEMCACHED_PORT}"



=== TEST 43: conn queuing: client aborting while connect operation is queued
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool_size = 1, backlog = 1}
            local sock1 = ngx.socket.connect("127.0.0.1", port, opts)

            local sock2 = ngx.socket.tcp()
            sock2:settimeouts(3000, 3000, 3000)
            local ok, err = sock2:connect("127.0.0.1", port, opts)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- ignore_response
--- timeout: 0.1
--- abort
--- no_error_log
[error]
--- curl_error eval
qr/curl: \(28\) Operation timed out after \d+ milliseconds with 0 bytes received/



=== TEST 44: conn queuing: resume next connect operation if resumed connect failed immediately
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "test", pool_size = 1, backlog = 2}

            local conn_sock = function(should_timeout)
                local sock = ngx.socket.tcp()
                local ok, err
                if should_timeout then
                    ok, err = sock:connect("", port, opts)
                else
                    ok, err = sock:connect("127.0.0.1", port, opts)
                end
                if not ok then
                    ngx.say(err)
                    return
                end
                ngx.say("connected in uthread")
                sock:close()
            end

            local sock, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not sock then
                ngx.log(ngx.ERR, err)
                return
            end

            local co1 = ngx.thread.spawn(conn_sock, true)
            local co2 = ngx.thread.spawn(conn_sock)

            local ok, err = sock:close()
            if not ok then
                ngx.log(ngx.ERR, err)
            end

            ngx.thread.wait(co1)
            ngx.thread.wait(co2)
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
failed to parse host name "": no host
connected in uthread
ok
--- no_error_log
[error]



=== TEST 45: conn queuing: resume connect operation if resumed connect failed (timeout)
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    resolver_timeout 3s;
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "test", pool_size = 1, backlog = 1}

            local conn_sock = function(should_timeout)
                local sock = ngx.socket.tcp()
                local ok, err
                if should_timeout then
                    sock:settimeouts(100, 3000, 3000)
                    ok, err = sock:connect("127.0.0.2", 12345, opts)
                else
                    ok, err = sock:connect("127.0.0.1", port, opts)
                end
                if not ok then
                    ngx.say(err)
                    return
                end
                ngx.say("connected in uthread")
                sock:close()
            end

            local co1 = ngx.thread.spawn(conn_sock, true)
            local co2 = ngx.thread.spawn(conn_sock)

            ngx.thread.wait(co1)
            ngx.thread.wait(co2)
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
timeout
connected in uthread
ok
--- error_log
queue connect operation for connection pool "test"
lua tcp socket connect timed out, upstream: 127.0.0.2:12345(127.0.0.2)



=== TEST 46: conn queuing: resume connect operation if resumed connect failed (could not be resolved)
--- quic_max_idle_timeout: 1.2
--- config
    resolver 127.0.0.2:12345 ipv6=off;
    resolver_timeout 1s;
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "test", pool_size = 1, backlog = 1}

            local conn_sock = function(should_timeout)
                local sock = ngx.socket.tcp()
                local ok, err
                if should_timeout then
                    sock:settimeouts(1, 3000, 3000)
                    ok, err = sock:connect("agentzh.org", 80, opts)
                else
                    ok, err = sock:connect("127.0.0.1", port, opts)
                end
                if not ok then
                    ngx.say(err)
                    return
                end
                ngx.say("connected in uthread")
                sock:close()
            end

            local co1 = ngx.thread.spawn(conn_sock, true)
            local co2 = ngx.thread.spawn(conn_sock)

            ngx.thread.wait(co1)
            ngx.thread.wait(co2)
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
agentzh.org could not be resolved (110: Operation timed out)
connected in uthread
ok
--- error_log
queue connect operation for connection pool "test"



=== TEST 47: conn queuing: resume connect operation if resumed connect failed (connection refused)
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "test", pool_size = 1, backlog = 1}

            local conn_sock = function(should_timeout)
                local sock = ngx.socket.tcp()
                local ok, err
                if should_timeout then
                    sock:settimeouts(100, 3000, 3000)
                    ok, err = sock:connect("127.0.0.1", 62345, opts)
                else
                    ok, err = sock:connect("127.0.0.1", port, opts)
                end
                if not ok then
                    ngx.say(err)
                    return
                end
                ngx.say("connected in uthread")
                sock:close()
            end

            local co1 = ngx.thread.spawn(conn_sock, true)
            local co2 = ngx.thread.spawn(conn_sock)

            ngx.thread.wait(co1)
            ngx.thread.wait(co2)
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
connection refused
connected in uthread
ok
--- error_log
queue connect operation for connection pool "test"



=== TEST 48: conn queuing: resume connect operation if resumed connect failed (uthread aborted while resolving)
--- http_config
    lua_package_path '../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;';
--- config
    resolver 127.0.0.1 ipv6=off;
    resolver_timeout 100s;
    set $port $TEST_NGINX_MEMCACHED_PORT;

    location /sub {
        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local sem = semaphore.new()

            local function f()
                sem:wait(0.1)
                ngx.exit(0)
            end

            local opts = {pool = "test", pool_size = 1, backlog = 1}
            local port = ngx.var.port
            ngx.timer.at(0, function()
                sem:post()
                local sock2, err = ngx.socket.connect("127.0.0.1", port, opts)
                package.loaded.for_timer_to_resume:post()
                if not sock2 then
                    ngx.log(ngx.ALERT, "resume connect failed: ", err)
                    return
                end

                ngx.log(ngx.INFO, "resume success")
            end)

            ngx.thread.spawn(f)
            local sock1, err = ngx.socket.connect("openresty.org", 80, opts)
            if not sock1 then
                ngx.say(err)
                return
            end
        }
    }

    location /t {
        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local for_timer_to_resume = semaphore.new()
            package.loaded.for_timer_to_resume = for_timer_to_resume

            ngx.location.capture("/sub")
            for_timer_to_resume:wait(0.1)
        }
    }
--- request
GET /t
--- no_error_log
[alert]
--- error_log
resume success



=== TEST 49: conn queuing: resume connect operation if resumed connect failed (uthread killed while resolving)
--- config
    resolver 127.0.0.1 ipv6=off;
    resolver_timeout 100s;
    set $port $TEST_NGINX_MEMCACHED_PORT;

    location /t {
        content_by_lua_block {
            local opts = {pool = "test", pool_size = 1, backlog = 1}
            local port = ngx.var.port

            local function resolve()
                local sock1, err = ngx.socket.connect("openresty.org", 80, opts)
                if not sock1 then
                    ngx.say(err)
                    return
                end
            end

            local th = ngx.thread.spawn(resolve)
            local ok, err = ngx.thread.kill(th)
            if not ok then
                ngx.log(ngx.ALERT, "kill thread failed: ", err)
                return
            end

            local sock2, err = ngx.socket.connect("127.0.0.1", port, opts)
            if not sock2 then
                ngx.log(ngx.ALERT, "resume connect failed: ", err)
                return
            end

            ngx.log(ngx.INFO, "resume success")
        }
    }
--- request
GET /t
--- no_error_log
[alert]
--- error_log
resume success



=== TEST 50: conn queuing: increase the counter for connections created before creating the pool with setkeepalive()
--- config
    set $port $TEST_NGINX_MEMCACHED_PORT;

    location /t {
        content_by_lua_block {
            local function connect()
                local sock, err = ngx.socket.connect("127.0.0.1", ngx.var.port)
                if not sock then
                    error("connect failed: " .. err)
                end

                return sock
            end

            local sock1 = connect()
            local sock2 = connect()
            assert(sock1:setkeepalive())
            assert(sock2:setkeepalive())

            local sock1 = connect()
            local sock2 = connect()
            assert(sock1:close())
            assert(sock2:close())

            ngx.say("ok")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
ok



=== TEST 51: conn queuing: only decrease the counter for connections which were counted by the pool
--- config
    set $port $TEST_NGINX_MEMCACHED_PORT;

    location /t {
        content_by_lua_block {
            local function connect()
                local sock, err = ngx.socket.connect("127.0.0.1", ngx.var.port)
                if not sock then
                    error("connect failed: " .. err)
                end

                return sock
            end

            local sock1 = connect()
            local sock2 = connect()
            assert(sock1:setkeepalive(1000, 1))
            assert(sock2:setkeepalive(1000, 1))

            local sock1 = connect()
            local sock2 = connect()
            assert(sock1:close())
            assert(sock2:close())

            ngx.say("ok")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
ok



=== TEST 52: conn queuing: clean up pending connect operations which are in queue
--- config
    set $port $TEST_NGINX_MEMCACHED_PORT;

    location /sub {
        content_by_lua_block {
            local opts = {pool = "test", pool_size = 1, backlog = 1}
            local sock, err = ngx.socket.connect("127.0.0.1", ngx.var.port, opts)
            if not sock then
                ngx.say("connect failed: " .. err)
                return
            end

            local function f()
                assert(ngx.socket.connect("127.0.0.1", ngx.var.port, opts))
            end

            local th = ngx.thread.spawn(f)
            local ok, err = ngx.thread.kill(th)
            if not ok then
                ngx.log(ngx.ERR, "kill thread failed: ", err)
                return
            end

            sock:close()
        }
    }

    location /t {
        content_by_lua_block {
            ngx.location.capture("/sub")
            -- let pending connect operation resumes first
            ngx.sleep(0)
            ngx.say("ok")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- error_log
lua tcp socket abort queueing
--- response_body
ok



=== TEST 53: custom pools in third parameters for unix domain socket
--- http_config eval
"
    lua_package_path '$::HtmlDir/?.lua;./?.lua;;';
    server {
        listen unix:$::HtmlDir/nginx.sock;
        default_type 'text/plain';

        server_tokens off;
        location /foo {
            echo foo;
            more_clear_headers Date;
        }
    }
"
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local test = require "test"
            local path = "$TEST_NGINX_HTML_DIR/nginx.sock";
            test.go(path, "A")
            test.go(path, "B")
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go(path, pool)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("unix:" .. path, nil, {pool = pool})
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok, ", reused: ", sock:getreusedtimes())

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end
end
--- request
GET /t
--- response_body
connected: 1, reused: 0
connected: 1, reused: 0
--- no_error_log eval
["[error]",
"lua tcp socket keepalive: free connection pool for ",
"lua tcp socket get keepalive peer: using connection"
]
--- error_log
lua tcp socket keepalive create connection pool for key "A"
lua tcp socket keepalive create connection pool for key "B"



=== TEST 54: wrong first argument for setkeepalive
--- no_http2
--- quic_max_idle_timeout: 1.2
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
   server_tokens off;
   location /t {
        keepalive_timeout 60s;

        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\r\nHost: localhost\r\nConnection: keepalive\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\r\n0\r\n\r\n")
            local data, err = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ok, err = sock:setkeepalive("not a number", "not a number")
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end
        }
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- error_code:
--- response_body
--- error_log eval
qr/\Qbad argument #1 to 'setkeepalive' (number expected, got string)\E/
--- no_error_log
[crit]
--- timeout: 4
--- curl_error eval
qr{HTTP/3 stream 0 reset by server}



=== TEST 55: wrong second argument for setkeepalive
--- no_http2
--- quic_max_idle_timeout: 1.2
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
   server_tokens off;
   location /t {
        keepalive_timeout 60s;

        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local port = ngx.var.port

            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.1\r\nHost: localhost\r\nConnection: keepalive\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local reader = sock:receiveuntil("\r\n0\r\n\r\n")
            local data, err = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response of ", #data, " bytes")

            ok, err = sock:setkeepalive()
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end

            ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ok, err = sock:setkeepalive(10, "not a number")
            if not ok then
                ngx.say("failed to set reusable: ", err)
            end
        }
    }

    location /foo {
        echo foo;
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- error_code:
--- response_body
--- error_log eval
qr/\Qbad argument #2 to 'setkeepalive' (number expected, got string)\E/
--- no_error_log
[crit]
--- timeout: 4
--- curl_error eval
qr{HTTP/3 stream 0 reset by server}



=== TEST 56: conn queuing: slots freed in the same cycle each resume a queued connect
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "same_cycle", pool_size = 2, backlog = 2}

            local sock1 = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local sock2 = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter(name)
                return ngx.thread.spawn(function()
                    local sock = ngx.socket.tcp()
                    sock:settimeouts(500, 500, 500)

                    local ok, err = sock:connect("127.0.0.1", port, opts)
                    if not ok then
                        return name .. ": " .. err
                    end

                    -- keep the slot past the other waiter's connect timeout,
                    -- so only a resumption can let it connect
                    ngx.sleep(1)
                    sock:close()
                    return name .. ": connected"
                end)
            end

            local w1 = waiter("w1")
            local w2 = waiter("w2")

            -- release both connections in the same cycle
            assert(sock1:setkeepalive())
            assert(sock2:setkeepalive())

            local _, res1 = ngx.thread.wait(w1)
            local _, res2 = ngx.thread.wait(w2)
            ngx.say(res1)
            ngx.say(res2)
        }
    }
--- request
GET /t
--- response_body
w1: connected
w2: connected
--- error_log
lua tcp socket queue connect operation for connection pool "same_cycle"
--- no_error_log
[error]
--- timeout: 4



=== TEST 57: conn queuing: close multiple connections before resumptions run
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local connected = semaphore.new()
            local release = semaphore.new()
            local port = ngx.var.port
            local opts = {pool = "same_cycle_close", pool_size = 2, backlog = 2}

            local sock1 = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local sock2 = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter(name)
                local sock = ngx.socket.tcp()
                sock:settimeout(500)
                assert(sock:connect("127.0.0.1", port, opts))
                local reused = sock:getreusedtimes()
                connected:post()
                assert(release:wait(2))
                sock:close()
                return name .. ": reused " .. reused
            end

            local w1 = ngx.thread.spawn(waiter, "w1")
            local w2 = ngx.thread.spawn(waiter, "w2")

            assert(sock1:close())
            assert(sock2:close())

            -- neither waiter may free its slot before both have connected
            assert(connected:wait(2))
            assert(connected:wait(2))
            release:post(2)

            local _, res1 = ngx.thread.wait(w1)
            local _, res2 = ngx.thread.wait(w2)
            ngx.say(res1)
            ngx.say(res2)
        }
    }
--- request
GET /t
--- response_body
w1: reused 0
w2: reused 0
--- error_log
lua tcp socket queue connect operation for connection pool "same_cycle_close"
--- no_error_log
[error]
--- timeout: 4



=== TEST 58: conn queuing: cancel a posted resumption and resume the next waiter
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local connected = semaphore.new()
            local release = semaphore.new()
            local port = ngx.var.port
            local opts = {pool = "cancel_posted", pool_size = 2, backlog = 3}
            local order = {}

            local sock1 = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local sock2 = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter(name)
                local sock = ngx.socket.tcp()
                sock:settimeout(500)
                assert(sock:connect("127.0.0.1", port, opts))
                order[#order + 1] = name
                local reused = sock:getreusedtimes()
                connected:post()
                assert(release:wait(2))
                sock:close()
                return name .. ": reused " .. reused
            end

            local w1 = ngx.thread.spawn(waiter, "w1")
            local w2 = ngx.thread.spawn(waiter, "w2")
            local w3 = ngx.thread.spawn(waiter, "w3")

            assert(sock1:setkeepalive())
            assert(sock2:setkeepalive())
            assert(ngx.thread.kill(w1))

            assert(connected:wait(2))
            assert(connected:wait(2))
            release:post(2)

            local _, res2 = ngx.thread.wait(w2)
            local _, res3 = ngx.thread.wait(w3)
            ngx.say(res2)
            ngx.say(res3)
            ngx.say("order: ", table.concat(order, ", "))
        }
    }
--- request
GET /t
--- response_body
w2: reused 1
w3: reused 1
order: w2, w3
--- error_log
lua tcp socket abort queueing
--- no_error_log
[error]
--- timeout: 4



=== TEST 59: conn queuing: advance past a timed out waiter
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        lua_socket_log_errors off;

        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local expired = semaphore.new()
            local port = ngx.var.port
            local opts = {pool = "expired_head", pool_size = 1, backlog = 2}
            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter1()
                local s = ngx.socket.tcp()
                s:settimeout(10)
                local ok, err = s:connect("127.0.0.1", port, opts)
                expired:post()
                return "w1: " .. (err or "connected")
            end

            local function waiter2()
                local s = ngx.socket.tcp()
                s:settimeout(500)
                assert(s:connect("127.0.0.1", port, opts))
                local reused = s:getreusedtimes()
                s:close()
                return "w2: reused " .. reused
            end

            local w1 = ngx.thread.spawn(waiter1)
            local w2 = ngx.thread.spawn(waiter2)
            assert(expired:wait(2))
            assert(sock:setkeepalive())

            local _, res1 = ngx.thread.wait(w1)
            local _, res2 = ngx.thread.wait(w2)
            ngx.say(res1)
            ngx.say(res2)
        }
    }
--- request
GET /t
--- response_body
w1: timeout
w2: reused 1
--- error_log
lua tcp socket queue connect operation for connection pool "expired_head"
--- no_error_log
[error]
--- timeout: 4



=== TEST 60: conn queuing: append after all existing waiters have been posted
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local connected = semaphore.new()
            local release = semaphore.new()
            local port = ngx.var.port
            local opts = {pool = "append_posted", pool_size = 1, backlog = 2}
            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter1()
                local s = ngx.socket.tcp()
                s:settimeout(500)
                assert(s:connect("127.0.0.1", port, opts))
                connected:post()
                assert(release:wait(2))
                s:close()
                return "w1: connected"
            end

            local function waiter2()
                local s = ngx.socket.tcp()
                s:settimeout(500)
                assert(s:connect("127.0.0.1", port, opts))
                s:close()
                return "w2: connected"
            end

            local w1 = ngx.thread.spawn(waiter1)
            assert(sock:close())
            local w2 = ngx.thread.spawn(waiter2)

            assert(connected:wait(2))
            release:post()
            local _, res1 = ngx.thread.wait(w1)
            local _, res2 = ngx.thread.wait(w2)
            ngx.say(res1)
            ngx.say(res2)
        }
    }
--- request
GET /t
--- response_body
w1: connected
w2: connected
--- error_log
lua tcp socket queue connect operation for connection pool "append_posted"
--- no_error_log
[error]
--- timeout: 4



=== TEST 61: conn queuing: a new connect does not take the idle connection handed to a queued one
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "queue_jump", pool_size = 1, backlog = 2}

            local sock1 = assert(ngx.socket.connect("127.0.0.1", port, opts))

            -- queued behind sock1, the only slot
            local waiter = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                assert(sock:connect("127.0.0.1", port, opts))
                local reused = sock:getreusedtimes()
                assert(sock:setkeepalive())
                return "waiter: reused " .. reused
            end)

            -- hand the slot to the waiter, whose resumption is only posted
            assert(sock1:setkeepalive())

            -- a connect in the same cycle must queue behind the waiter: taking
            -- the idle connection would make the waiter open a second one
            local sock3 = ngx.socket.tcp()
            sock3:settimeout(1000)
            assert(sock3:connect("127.0.0.1", port, opts))
            local reused = sock3:getreusedtimes()
            sock3:close()

            local _, res = ngx.thread.wait(waiter)
            ngx.say(res)
            ngx.say("newcomer: reused ", reused)
        }
    }
--- request
GET /t
--- response_body
waiter: reused 1
newcomer: reused 2
--- error_log
lua tcp socket queue connect operation for connection pool "queue_jump"
--- no_error_log
[error]



=== TEST 62: conn queuing: a new connect reuses an idle connection no queued one was resumed for
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "spare_idle", pool_size = 2, backlog = 2}

            local sock1 = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local sock2 = assert(ngx.socket.connect("127.0.0.1", port, opts))

            -- queued behind sock1 and sock2
            local waiter = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                assert(sock:connect("127.0.0.1", port, opts))
                local reused = sock:getreusedtimes()
                -- hold the connection past the newcomer's connect timeout
                ngx.sleep(0.5)
                assert(sock:setkeepalive())
                return "waiter: reused " .. reused
            end)

            -- two connections come back, one of them is handed to the waiter
            assert(sock1:setkeepalive())
            assert(sock2:setkeepalive())

            -- the other one is free to reuse: queuing behind the waiter would
            -- time out while it sits idle
            local sock3 = ngx.socket.tcp()
            sock3:settimeout(200)
            local ok, err = sock3:connect("127.0.0.1", port, opts)
            local res = ok and "newcomer: reused " .. sock3:getreusedtimes()
                        or "newcomer: " .. err
            if ok then
                sock3:close()
            end

            local _, wres = ngx.thread.wait(waiter)
            ngx.say(wres)
            ngx.say(res)
        }
    }
--- request
GET /t
--- response_body
waiter: reused 1
newcomer: reused 1
--- error_log
lua tcp socket queue connect operation for connection pool "spare_idle"
--- no_error_log
[error]
--- timeout: 4



=== TEST 63: conn queuing: a cancelled resumed connect passes its idle connection to the next one
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "pass_reserved", pool_size = 1, backlog = 3}

            local sock1 = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter(name)
                return ngx.thread.spawn(function()
                    local sock = ngx.socket.tcp()
                    sock:settimeout(1000)
                    assert(sock:connect("127.0.0.1", port, opts))
                    local reused = sock:getreusedtimes()
                    assert(sock:setkeepalive())
                    return name .. ": reused " .. reused
                end)
            end

            local w1 = waiter("w1")
            local w2 = waiter("w2")

            -- hand the only connection to w1, then cancel w1 before it runs
            assert(sock1:setkeepalive())
            assert(ngx.thread.kill(w1))

            -- the connection now belongs to w2, not to a new connect
            local sock3 = ngx.socket.tcp()
            sock3:settimeout(1000)
            assert(sock3:connect("127.0.0.1", port, opts))
            local reused = sock3:getreusedtimes()
            sock3:close()

            local _, res = ngx.thread.wait(w2)
            ngx.say(res)
            ngx.say("newcomer: reused ", reused)
        }
    }
--- request
GET /t
--- response_body
w2: reused 1
newcomer: reused 2
--- error_log
lua tcp socket queue connect operation for connection pool "pass_reserved"
--- no_error_log
[error]



=== TEST 64: conn queuing: cancelling a queued connect frees no slot
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "cancel_queued", pool_size = 1, backlog = 2}

            local sock1 = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter(name)
                return ngx.thread.spawn(function()
                    local sock = ngx.socket.tcp()
                    sock:settimeout(300)
                    local ok, err = sock:connect("127.0.0.1", port, opts)
                    if not ok then
                        return name .. ": " .. err
                    end
                    local reused = sock:getreusedtimes()
                    sock:close()
                    return name .. ": reused " .. reused
                end)
            end

            local w1 = waiter("w1")
            local w2 = waiter("w2")

            -- w1 never got a slot: cancelling it must not let w2 connect while
            -- sock1 still holds the only one
            assert(ngx.thread.kill(w1))

            local _, res = ngx.thread.wait(w2)
            ngx.say(res)
            sock1:close()
        }
    }
--- request
GET /t
--- response_body
w2: timeout
--- error_log
lua tcp socket queue connect operation for connection pool "cancel_queued"
--- no_error_log
[alert]



=== TEST 65: conn queuing: a resumed connect cancelled after its idle connection closed hands the slot on
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "reserved_closed", pool_size = 1, backlog = 2}

            local sock1 = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter(name)
                return ngx.thread.spawn(function()
                    local sock = ngx.socket.tcp()
                    sock:settimeout(500)
                    local ok, err = sock:connect("127.0.0.1", port, opts)
                    if not ok then
                        return name .. ": " .. err
                    end
                    local reused = sock:getreusedtimes()
                    sock:close()
                    return name .. ": reused " .. reused
                end)
            end

            local w1 = waiter("w1")
            local w2 = waiter("w2")

            -- runs once this thread sleeps below: its 1ms keepalive timer
            -- is then ahead of the sleep timer, and both expire in this
            -- cycle before w1's posted resumption runs
            local spinner = ngx.thread.spawn(function()
                coroutine.yield()

                -- hand the only connection to w1, to be closed before w1 runs
                assert(sock1:setkeepalive(1))

                local t = ngx.now()
                repeat
                    ngx.update_time()
                until ngx.now() - t >= 0.005
            end)

            -- wakes up after the reserved connection closed, to cancel w1
            ngx.sleep(0.002)
            local killed, err = ngx.thread.kill(w1)
            ngx.thread.wait(spinner)

            local _, res = ngx.thread.wait(w2)
            ngx.say("killed: ", killed or err)
            ngx.say(res)
        }
    }
--- request
GET /t
--- response_body
killed: 1
w2: reused 0
--- error_log
lua tcp socket queue connect operation for connection pool "reserved_closed"
--- no_error_log
[error]



=== TEST 66: conn queuing: a pre-pool connection cannot replace an assigned connection
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local pool = "replace_reserved"
            local legacy = assert(ngx.socket.connect("127.0.0.1", port,
                                                    {pool = pool}))
            local opts = {pool = pool, pool_size = 1, backlog = 2}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            assert(holder:setkeepalive())
            holder = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local waiter = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                assert(sock:connect("127.0.0.1", port, opts))
                local reused = sock:getreusedtimes()
                assert(sock:setkeepalive())
                return "waiter: reused " .. reused
            end)

            -- The already reused connection belongs to the posted waiter;
            -- a pre-pool connection must not replace it or take its slot.
            assert(holder:setkeepalive())
            assert(legacy:setkeepalive())

            local newcomer = ngx.socket.tcp()
            newcomer:settimeout(1000)
            assert(newcomer:connect("127.0.0.1", port, opts))
            local reused = newcomer:getreusedtimes()
            local ok, res = ngx.thread.wait(waiter)
            assert(ok, res)

            -- Hold the newcomer open: there must be no second live connection
            -- available in this pool of size one.
            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local connected, err = extra:connect("127.0.0.1", port, opts)
            ngx.say(res)
            ngx.say("newcomer: reused ", reused)
            ngx.say("extra: ", connected or err)
            if connected then
                extra:close()
            end

            newcomer:close()
        }
    }
--- request
GET /t
--- response_body
waiter: reused 2
newcomer: reused 3
extra: timeout
--- error_log
lua tcp socket queue connect operation for connection pool "replace_reserved"
--- no_error_log
[error]



=== TEST 67: conn queuing: a pre-pool connection cannot wake another waiter after handoff
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local connected = semaphore.new()
            local release = semaphore.new()
            local port = ngx.var.port
            local pool = "replace_reserved_waiters"
            local legacy = assert(ngx.socket.connect("127.0.0.1", port,
                                                    {pool = pool}))
            local opts = {pool = pool, pool_size = 1, backlog = 2}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            assert(holder:setkeepalive())
            holder = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local w1 = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                assert(sock:connect("127.0.0.1", port, opts))
                local reused = sock:getreusedtimes()
                connected:post()
                assert(release:wait(2))
                sock:close()
                return "w1: reused " .. reused
            end)

            local w2 = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(100)
                local ok, err = sock:connect("127.0.0.1", port, opts)
                if not ok then
                    return "w2: " .. err
                end

                local reused = sock:getreusedtimes()
                sock:close()
                return "w2: reused " .. reused
            end)

            -- Returning a pre-pool connection must neither replace w1's
            -- assigned connection nor resume w2 for the same slot.
            assert(holder:setkeepalive())
            assert(legacy:setkeepalive())
            assert(connected:wait(2))

            local ok, res2 = ngx.thread.wait(w2)
            assert(ok, res2)
            release:post()
            local ok, res1 = ngx.thread.wait(w1)
            assert(ok, res1)
            ngx.say(res1)
            ngx.say(res2)
        }
    }
--- request
GET /t
--- response_body
w1: reused 2
w2: timeout
--- error_log
lua tcp socket queue connect operation for connection pool "replace_reserved_waiters"
--- no_error_log
[error]
--- timeout: 4



=== TEST 68: conn queuing: a pre-pool connection cannot take a posted slot
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local pool = "legacy_posted_slot"
            local legacy = assert(ngx.socket.connect("127.0.0.1", port,
                                                    {pool = pool}))
            local opts = {pool = pool, pool_size = 1, backlog = 2}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local waiter = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                assert(sock:connect("127.0.0.1", port, opts))
                local reused = sock:getreusedtimes()
                assert(sock:setkeepalive())
                return "waiter: reused " .. reused
            end)

            -- The freed slot belongs to the posted waiter. The uncounted
            -- legacy connection must be closed rather than added to cache.
            assert(holder:close())
            assert(legacy:setkeepalive())

            local newcomer = ngx.socket.tcp()
            newcomer:settimeout(1000)
            assert(newcomer:connect("127.0.0.1", port, opts))
            local reused = newcomer:getreusedtimes()
            local ok, res = ngx.thread.wait(waiter)
            assert(ok, res)

            -- Hold the newcomer open: there must be no second live connection
            -- available in this pool of size one.
            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local connected, err = extra:connect("127.0.0.1", port, opts)
            ngx.say(res)
            ngx.say("newcomer: reused ", reused)
            ngx.say("extra: ", connected or err)
            if connected then
                extra:close()
            end

            newcomer:close()
        }
    }
--- request
GET /t
--- response_body
waiter: reused 0
newcomer: reused 1
extra: timeout
--- error_log
lua tcp socket queue connect operation for connection pool "legacy_posted_slot"
--- no_error_log
[error]



=== TEST 69: conn queuing: a pre-pool connection frees no second posted slot
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local connected = semaphore.new()
            local release = semaphore.new()
            local port = ngx.var.port
            local pool = "legacy_posted_waiters"
            local legacy = assert(ngx.socket.connect("127.0.0.1", port,
                                                    {pool = pool}))
            local opts = {pool = pool, pool_size = 1, backlog = 2}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local w1 = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                assert(sock:connect("127.0.0.1", port, opts))
                local reused = sock:getreusedtimes()
                connected:post()
                assert(release:wait(2))
                sock:close()
                return "w1: reused " .. reused
            end)

            local w2 = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(100)
                local ok, err = sock:connect("127.0.0.1", port, opts)
                if not ok then
                    return "w2: " .. err
                end

                local reused = sock:getreusedtimes()
                sock:close()
                return "w2: reused " .. reused
            end)

            -- The close hands the only slot to w1. Returning an uncounted
            -- connection must not also resume w2 for that same slot.
            assert(holder:close())
            assert(legacy:setkeepalive())
            assert(connected:wait(2))

            local ok, res2 = ngx.thread.wait(w2)
            assert(ok, res2)
            release:post()
            local ok, res1 = ngx.thread.wait(w1)
            assert(ok, res1)
            ngx.say(res1)
            ngx.say(res2)
        }
    }
--- request
GET /t
--- response_body
w1: reused 0
w2: timeout
--- error_log
lua tcp socket queue connect operation for connection pool "legacy_posted_waiters"
--- no_error_log
[error]
--- timeout: 4



=== TEST 70: conn queuing: a pre-pool connection cannot exceed a busy pool
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local pool = "legacy_busy_pool"
            local legacy = assert(ngx.socket.connect("127.0.0.1", port,
                                                    {pool = pool}))
            local opts = {pool = pool, pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            assert(legacy:setkeepalive())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local ok, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", ok or err)
            if ok then
                extra:close()
            end

            assert(holder:close())
            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("after close: reused ", sock:getreusedtimes())
            sock:close()
        }
    }
--- request
GET /t
--- response_body
extra: timeout
after close: reused 0
--- error_log
lua tcp socket queue connect operation for connection pool "legacy_busy_pool"
--- no_error_log
[error]



=== TEST 71: conn queuing: a pre-pool connection can use spare capacity
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local pool = "legacy_spare_capacity"
            local legacy = assert(ngx.socket.connect("127.0.0.1", port,
                                                    {pool = pool}))
            local opts = {pool = pool, pool_size = 2, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            assert(legacy:setkeepalive())

            local newcomer = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("newcomer: reused ", newcomer:getreusedtimes())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local ok, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", ok or err)
            if ok then
                extra:close()
            end

            newcomer:close()
            holder:close()
        }
    }
--- request
GET /t
--- response_body
newcomer: reused 1
extra: timeout
--- error_log
lua tcp socket queue connect operation for connection pool "legacy_spare_capacity"
--- no_error_log
[error]



=== TEST 72: conn queuing: a posted reuse leaves spare capacity available
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local ready = semaphore.new()
            local release = semaphore.new()
            local port = ngx.var.port
            local opts = {pool = "posted_reuse_capacity", pool_size = 2,
                          backlog = 3}
            local holder1 = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local holder2 = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local waiter = ngx.thread.spawn(function()
                local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
                local reused = sock:getreusedtimes()
                ready:post()
                assert(release:wait(2))
                sock:close()
                return "waiter: reused " .. reused
            end)

            assert(holder1:setkeepalive())
            assert(holder2:close())

            -- The waiter owns holder1's connection. The slot closed by
            -- holder2 is available even before that posted reuse runs.
            local newcomer = ngx.socket.tcp()
            newcomer:settimeout(100)
            local ok, err = newcomer:connect("127.0.0.1", port, opts)
            local res = ok and "newcomer: reused " .. newcomer:getreusedtimes()
                           or "newcomer: " .. err
            assert(ready:wait(2))

            -- Both slots are now occupied: subtracting the reservation must
            -- not give another caller a third slot.
            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local connected, extra_err = extra:connect("127.0.0.1", port, opts)
            if connected then
                extra:close()
            end

            if ok then
                newcomer:close()
            end

            release:post()
            local waited, wres = ngx.thread.wait(waiter)
            assert(waited, wres)
            ngx.say(wres)
            ngx.say(res)
            ngx.say("extra: ", connected or extra_err)
        }
    }
--- request
GET /t
--- response_body
waiter: reused 1
newcomer: reused 0
extra: timeout
--- error_log
lua tcp socket queue connect operation for connection pool "posted_reuse_capacity"
--- no_error_log
[error]
--- timeout: 4



=== TEST 73: conn queuing: a reserved connection does not consume backlog twice
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "reserved_backlog", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter(name)
                return ngx.thread.spawn(function()
                    local sock = ngx.socket.tcp()
                    sock:settimeout(1000)
                    local ok, err = sock:connect("127.0.0.1", port, opts)
                    if not ok then
                        return name .. ": " .. err
                    end

                    local reused = sock:getreusedtimes()
                    assert(sock:setkeepalive())
                    return name .. ": reused " .. reused
                end)
            end

            local w1 = waiter("w1")
            assert(holder:setkeepalive())

            -- w1 already owns the connection. Only w2 uses the backlog slot;
            -- the next connect must still be rejected while it waits.
            local w2 = waiter("w2")
            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local ok, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", ok or err)
            if ok then
                extra:close()
            end

            local ok1, res1 = ngx.thread.wait(w1)
            local ok2, res2 = ngx.thread.wait(w2)
            assert(ok1, res1)
            assert(ok2, res2)
            ngx.say(res1)
            ngx.say(res2)
        }
    }
--- request
GET /t
--- response_body
extra: too many waiting connect operations
w1: reused 1
w2: reused 2
--- error_log
lua tcp socket queue connect operation for connection pool "reserved_backlog"
--- no_error_log
[error]



=== TEST 74: conn queuing: cancelling the last posted waiter releases its reservation
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "cancel_last_reserved", pool_size = 1,
                          backlog = 2}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local waiter = ngx.thread.spawn(function()
                assert(ngx.socket.connect("127.0.0.1", port, opts))
                error("cancelled waiter resumed")
            end)

            assert(holder:setkeepalive())
            assert(ngx.thread.kill(waiter))
            local newcomer = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("newcomer: reused ", newcomer:getreusedtimes())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local ok, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", ok or err)
            if ok then
                extra:close()
            end

            newcomer:close()
        }
    }
--- request
GET /t
--- response_body
newcomer: reused 1
extra: timeout
--- error_log
lua tcp socket queue connect operation for connection pool "cancel_last_reserved"
--- no_error_log
[error]



=== TEST 75: conn queuing: request cleanup releases an unexecuted handoff
--- config
    set $port $TEST_NGINX_SERVER_PORT;

    location /abort {
        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "aborted_handoff", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.thread.spawn(function()
                assert(ngx.socket.connect("127.0.0.1", port, opts))
                error("aborted waiter resumed")
            end)

            assert(holder:setkeepalive())
            return ngx.exit(204)
        }
    }

    location /t {
        lua_socket_log_errors off;
        content_by_lua_block {
            local res = ngx.location.capture("/abort")
            local port = ngx.var.port
            local opts = {pool = "aborted_handoff", pool_size = 1, backlog = 1}
            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("status: ", res.status)
            ngx.say("reused: ", sock:getreusedtimes())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local ok, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", ok or err)
            if ok then
                extra:close()
            end

            sock:close()
        }
    }
--- request
GET /t
--- response_body
status: 204
reused: 1
extra: timeout
--- error_log
lua tcp socket abort queueing
--- no_error_log
[error]



=== TEST 76: conn queuing: cancelling an owner cannot release a recycled item
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "recycled_handoff", pool_size = 2, backlog = 2}
            local holder1 = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local holder2 = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter(name)
                return ngx.thread.spawn(function()
                    local sock = ngx.socket.tcp()
                    sock:settimeout(500)
                    assert(sock:connect("127.0.0.1", port, opts))
                    local reused = sock:getreusedtimes()
                    assert(sock:setkeepalive())
                    return name .. ": reused " .. reused
                end)
            end

            local w1 = waiter("w1")
            local w2 = waiter("w2")
            local spinner = ngx.thread.spawn(function()
                coroutine.yield()
                assert(holder1:setkeepalive(1))

                local t = ngx.now()
                repeat
                    ngx.update_time()
                until ngx.now() - t >= 0.005
            end)

            ngx.sleep(0.002)

            -- w1's connection closed, returning its item to the free list.
            -- Reuse that item for w2 before cancelling w1: the cancellation
            -- must release only w1's empty slot, leaving w2's connection alone.
            assert(holder2:setkeepalive())
            local killed, err = ngx.thread.kill(w1)
            assert(killed, err)
            assert(ngx.thread.wait(spinner))

            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local reused = sock:getreusedtimes()
            local ok, res = ngx.thread.wait(w2)
            assert(ok, res)
            ngx.say("killed: ", killed)
            ngx.say(res)
            ngx.say("newcomer: reused ", reused)
            sock:close()
        }
    }
--- request
GET /t
--- response_body
killed: 1
w2: reused 1
newcomer: reused 0
--- error_log
lua tcp socket keepalive max idle timeout
--- no_error_log
[error]



=== TEST 77: conn queuing: reconnect cannot overwrite a waiting socket
--- config
    location /t {
        content_by_lua_block {
            local port = ngx.var.server_port
            local opts = {pool = "busy_queued", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local sock = ngx.socket.tcp()
            sock:settimeout(1000)
            local waiter = ngx.thread.spawn(function()
                assert(sock:connect("127.0.0.1", port, opts))
                error("cancelled waiter resumed")
            end)

            local other = {pool = "busy_other", pool_size = 1, backlog = 1}
            local ok, err = sock:connect("127.0.0.1", port, other)
            ngx.say("second: ", ok or err)
            ngx.say("killed: ", assert(ngx.thread.kill(waiter)))
            holder:close()

            -- Cancellation clears the busy state before this socket is reused.
            assert(sock:connect("127.0.0.1", port, other))
            ngx.say("retry: reused ", sock:getreusedtimes())
            sock:close()
        }
    }
--- request
GET /t
--- response_body
second: socket busy connecting
killed: 1
retry: reused 0
--- error_log
lua tcp socket abort queueing
--- no_error_log
[error]



=== TEST 78: conn queuing: rejected reconnect preserves a posted socket's pool
--- config
    location /t {
        content_by_lua_block {
            local port = ngx.var.server_port
            local opts = {pool = "busy_posted", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local sock = ngx.socket.tcp()
            local waiter = ngx.thread.spawn(function()
                assert(sock:connect("127.0.0.1", port, opts))
                assert(sock:setkeepalive())
            end)

            assert(holder:setkeepalive())
            local other = {pool = "posted_other", pool_size = 1, backlog = 1}
            local ok, err = sock:connect("127.0.0.1", port, other)
            ngx.say("second: ", ok or err)
            assert(ngx.thread.wait(waiter))

            local next_sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("original pool: reused ", next_sock:getreusedtimes())
            next_sock:close()
        }
    }
--- request
GET /t
--- response_body
second: socket busy connecting
original pool: reused 2
--- error_log
lua tcp socket queue connect operation for connection pool "busy_posted"
--- no_error_log
[error]



=== TEST 79: conn queuing: a timed out socket can connect again
--- config
    location /t {
        lua_socket_log_errors off;
        content_by_lua_block {
            local port = ngx.var.server_port
            local opts = {pool = "busy_timeout", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local sock = ngx.socket.tcp()
            sock:settimeout(50)
            local waiter = ngx.thread.spawn(function()
                local ok, err = sock:connect("127.0.0.1", port, opts)
                return ok or err
            end)
            local ok, res = ngx.thread.wait(waiter)
            assert(ok, res)
            ngx.say("first: ", res)

            sock:settimeout(1000)
            local other = {pool = "timeout_retry", pool_size = 1, backlog = 1}
            assert(sock:connect("127.0.0.1", port, other))
            ngx.say("retry: reused ", sock:getreusedtimes())
            sock:close()
            holder:close()
        }
    }
--- request
GET /t
--- response_body
first: timeout
retry: reused 0
--- error_log
lua tcp socket queue connect operation for connection pool "busy_timeout"
--- no_error_log
[error]



=== TEST 80: conn queuing: a socket cancelled after handoff can connect again
--- config
    location /t {
        content_by_lua_block {
            local port = ngx.var.server_port
            local opts = {pool = "busy_cancelled", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local sock = ngx.socket.tcp()
            local waiter = ngx.thread.spawn(function()
                assert(sock:connect("127.0.0.1", port, opts))
                error("cancelled waiter resumed")
            end)

            assert(holder:setkeepalive())
            ngx.say("killed: ", assert(ngx.thread.kill(waiter)))
            assert(sock:connect("127.0.0.1", port, opts))
            ngx.say("retry: reused ", sock:getreusedtimes())
            sock:close()
        }
    }
--- request
GET /t
--- response_body
killed: 1
retry: reused 1
--- error_log
lua tcp socket abort queueing
--- no_error_log
[error]



=== TEST 81: conn queuing: killing a parent cancels its posted child coroutine
--- config
    location /t {
        lua_socket_log_errors off;
        content_by_lua_block {
            local port = ngx.var.server_port
            local opts = {pool = "nested_cancel", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local parent = ngx.thread.spawn(function()
                coroutine.wrap(function()
                    local sock = ngx.socket.tcp()
                    assert(sock:connect("127.0.0.1", port, opts))
                    error("cancelled descendant resumed")
                end)()
            end)

            assert(holder:setkeepalive())
            assert(ngx.thread.kill(parent))
            parent = nil
            collectgarbage("collect")
            collectgarbage("collect")

            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("reused: ", sock:getreusedtimes())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local ok, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", ok or err)
            if ok then
                assert(extra:close())
            end

            assert(sock:close())
        }
    }
--- request
GET /t
--- response_body
reused: 1
extra: timeout
--- error_log
lua tcp socket abort queueing
--- no_error_log
[error]



=== TEST 82: conn queuing: internal redirect cancels an unexecuted content handoff
--- config
    location /t {
        content_by_lua_block {
            local port = ngx.var.server_port
            local opts = {pool = "exec_cancel", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                assert(sock:connect("127.0.0.1", port, opts))
                error("redirected waiter resumed")
            end)

            assert(holder:setkeepalive())
            return ngx.exec("/after")
        }
    }

    location /after {
        lua_socket_log_errors off;
        content_by_lua_block {
            collectgarbage("collect")
            collectgarbage("collect")

            local opts = {pool = "exec_cancel", pool_size = 1, backlog = 1}
            local port = ngx.var.server_port
            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("reused: ", sock:getreusedtimes())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local ok, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", ok or err)
            if ok then
                assert(extra:close())
            end

            assert(sock:close())
        }
    }
--- request
GET /t
--- response_body
reused: 1
extra: timeout
--- error_log
lua tcp socket abort queueing
--- no_error_log
[error]



=== TEST 83: conn queuing: internal redirect cancels an unexecuted rewrite handoff
--- config
    location /t {
        rewrite_by_lua_block {
            local port = ngx.var.server_port
            local opts = {pool = "rewrite_exec_cancel", pool_size = 1,
                          backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                assert(sock:connect("127.0.0.1", port, opts))
                error("redirected waiter resumed")
            end)

            assert(holder:setkeepalive())
            return ngx.exec("/after")
        }

        content_by_lua_block {
            error("old content executed")
        }
    }

    location /after {
        lua_socket_log_errors off;
        content_by_lua_block {
            collectgarbage("collect")
            collectgarbage("collect")

            local opts = {pool = "rewrite_exec_cancel", pool_size = 1,
                          backlog = 1}
            local port = ngx.var.server_port
            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("reused: ", sock:getreusedtimes())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local ok, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", ok or err)
            if ok then
                assert(extra:close())
            end

            assert(sock:close())
        }
    }
--- request
GET /t
--- response_body
reused: 1
extra: timeout
--- error_log
lua tcp socket abort queueing
--- no_error_log
[error]



=== TEST 84: conn queuing: internal redirect cancels an unexecuted access handoff
--- config
    location /t {
        access_by_lua_block {
            local port = ngx.var.server_port
            local opts = {pool = "access_exec_cancel", pool_size = 1,
                          backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                assert(sock:connect("127.0.0.1", port, opts))
                error("redirected waiter resumed")
            end)

            assert(holder:setkeepalive())
            return ngx.exec("/after")
        }

        content_by_lua_block {
            error("old content executed")
        }
    }

    location /after {
        lua_socket_log_errors off;
        content_by_lua_block {
            collectgarbage("collect")
            collectgarbage("collect")

            local opts = {pool = "access_exec_cancel", pool_size = 1,
                          backlog = 1}
            local port = ngx.var.server_port
            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("reused: ", sock:getreusedtimes())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local ok, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", ok or err)
            if ok then
                assert(extra:close())
            end

            assert(sock:close())
        }
    }
--- request
GET /t
--- response_body
reused: 1
extra: timeout
--- error_log
lua tcp socket abort queueing
--- no_error_log
[error]



=== TEST 85: conn queuing: a stale connection returned to the pool passes its slot to a waiter
--- config
    set $port $TEST_NGINX_SERVER_PORT;

    location = /ka {
        return 200 "ok";
    }

    location /t {
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "stale_handoff", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local waiter = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                local ok, err = sock:connect("127.0.0.1", port, opts)
                if not ok then
                    return "waiter: " .. err
                end

                local reused = sock:getreusedtimes()
                assert(sock:setkeepalive())
                return "waiter: reused " .. reused
            end)

            local req = "GET /ka HTTP/1.1\r\nHost: localhost\r\n\r\n"
            assert(holder:send(req))
            local read_headers = holder:receiveuntil("\r\n\r\n")
            assert(read_headers())
            assert(holder:receive(2))

            -- An unread response makes the connection readable when it goes
            -- back to the pool: it is closed there, and its slot must go to
            -- the waiter exactly once.
            assert(holder:send(req))
            ngx.sleep(0.05)

            local ok, err = holder:setkeepalive()
            ngx.say("setkeepalive: ", ok or err)

            local ok, res = ngx.thread.wait(waiter)
            assert(ok, res)
            ngx.say(res)

            local sock = ngx.socket.tcp()
            sock:settimeout(1000)
            assert(sock:connect("127.0.0.1", port, opts))
            ngx.say("newcomer: reused ", sock:getreusedtimes())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local connected, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", connected or err)
            if connected then
                extra:close()
            end

            sock:close()
        }
    }
--- request
GET /t
--- response_body
setkeepalive: connection in dubious state
waiter: reused 0
newcomer: reused 1
extra: timeout
--- error_log
lua tcp socket keepalive close handler: fd:
--- no_error_log
[error]



=== TEST 86: conn queuing: waiters refused by the backend pass their slots on
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "refused_backend", pool_size = 1, backlog = 2}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local function waiter(name)
                return ngx.thread.spawn(function()
                    local sock = ngx.socket.tcp()
                    sock:settimeout(1000)
                    ngx.update_time()
                    local start = ngx.now()

                    -- nothing listens on port 1
                    local ok, err = sock:connect("127.0.0.1", 1, opts)
                    ngx.update_time()
                    local slow = ngx.now() - start >= 0.5 and " (slow)" or ""
                    if ok then
                        sock:close()
                        return name .. ": connected" .. slow
                    end

                    return name .. ": " .. err .. slow
                end)
            end

            local w1 = waiter("w1")
            local w2 = waiter("w2")

            -- Each refused waiter must hand the slot to the next one
            -- instead of leaving it to the connect timeout.
            assert(holder:close())

            for _, th in ipairs({w1, w2}) do
                local ok, res = ngx.thread.wait(th)
                assert(ok, res)
                ngx.say(res)
            end

            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("after: reused ", sock:getreusedtimes())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local connected, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", connected or err)
            if connected then
                extra:close()
            end

            sock:close()
        }
    }
--- request
GET /t
--- response_body
w1: connection refused
w2: connection refused
after: reused 0
extra: timeout
--- error_log
lua tcp socket queue connect operation for connection pool "refused_backend"
--- no_error_log
[error]



=== TEST 87: conn queuing: a request ending without closing its socket resumes a waiter
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "unclosed_holder", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))

            assert(ngx.timer.at(0, function()
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                local ok, err = sock:connect("127.0.0.1", port, opts)
                if not ok then
                    ngx.log(ngx.WARN, "waiter: ", err)
                    return
                end

                local reused = sock:getreusedtimes()
                local extra = ngx.socket.tcp()
                extra:settimeout(50)
                local connected, cerr = extra:connect("127.0.0.1", port, opts)
                if connected then
                    extra:close()
                end

                sock:close()
                ngx.log(ngx.WARN, "waiter: reused ", reused, ", extra: ",
                        connected or cerr)
            end))

            -- let the timer queue behind the holder
            ngx.sleep(0.01)
            ngx.say(holder and "done")

            -- the holder is left open: the request cleanup closes it and
            -- must hand its slot to the waiting timer
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
waiter: reused 0, extra: timeout
--- no_error_log
[error]
--- wait: 0.5



=== TEST 88: conn queuing: a waiter cancelled by the end of its request frees its backlog place
--- config
    set $port $TEST_NGINX_SERVER_PORT;

    location /sub {
        content_by_lua_block {
            local opts = {pool = "ended_waiter", pool_size = 1, backlog = 1}
            ngx.thread.spawn(function()
                assert(ngx.socket.connect("127.0.0.1", ngx.var.port, opts))
                error("cancelled waiter resumed")
            end)

            return ngx.exit(200)
        }
    }

    location /t {
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "ended_waiter", pool_size = 1, backlog = 1}
            local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local res = ngx.location.capture("/sub")

            -- the subrequest's waiter was cancelled while still queued, so
            -- the only backlog place must be free again
            local newcomer = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                local ok, err = sock:connect("127.0.0.1", port, opts)
                if not ok then
                    return "newcomer: " .. err
                end

                local reused = sock:getreusedtimes()
                sock:close()
                return "newcomer: reused " .. reused
            end)

            assert(holder:setkeepalive())
            local ok, r = ngx.thread.wait(newcomer)
            assert(ok, r)
            ngx.say("status: ", res.status)
            ngx.say(r)
        }
    }
--- request
GET /t
--- response_body
status: 200
newcomer: reused 1
--- error_log
lua tcp socket abort queueing
--- no_error_log
[error]



=== TEST 89: conn queuing: a reconnect rejected as busy reading keeps the socket's pool
--- config
    set $port $TEST_NGINX_SERVER_PORT;

    location = /ka {
        return 200 "ok";
    }

    location /t {
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local sock = ngx.socket.tcp()
            assert(sock:connect("127.0.0.1", port, {pool = "reading_pool"}))
            assert(sock:send("GET /ka HTTP/1.1\r\nHost: localhost\r\n\r\n"))

            local reader = ngx.thread.spawn(function()
                local read_headers = sock:receiveuntil("\r\n\r\n")
                assert(read_headers())
                return assert(sock:receive(2))
            end)

            -- rejected while the reader waits: the pool key must not change
            local ok, err = sock:connect("127.0.0.1", port, {pool = "other_pool"})
            ngx.say("reconnect: ", ok or err)

            local ok, body = ngx.thread.wait(reader)
            assert(ok, body)
            assert(sock:setkeepalive())

            local again = assert(ngx.socket.connect("127.0.0.1", port,
                                                    {pool = "reading_pool"}))
            ngx.say("reading_pool: reused ", again:getreusedtimes())
            again:close()
        }
    }
--- request
GET /t
--- response_body
reconnect: socket busy reading
reading_pool: reused 1
--- error_log
lua tcp socket keepalive create connection pool for key "reading_pool"
--- no_error_log
[error]



=== TEST 90: conn queuing: a pre-pool connection replaces an idle connection in a full pool
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local pool = "legacy_replaces_idle"
            local legacy = assert(ngx.socket.connect("127.0.0.1", port,
                                                    {pool = pool}))
            local opts = {pool = pool, pool_size = 2, backlog = 1}

            -- fill the pool: one active connection and one idle connection,
            -- reused once, while a free item is still left
            local idle = assert(ngx.socket.connect("127.0.0.1", port, opts))
            assert(idle:setkeepalive())
            idle = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local active = assert(ngx.socket.connect("127.0.0.1", port, opts))
            assert(idle:setkeepalive())

            -- the uncounted connection may only take the idle one's place
            assert(legacy:setkeepalive())

            local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
            ngx.say("reused: ", sock:getreusedtimes())

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local connected, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", connected or err)
            if connected then
                extra:close()
            end

            sock:close()
            active:close()
        }
    }
--- request
GET /t
--- response_body
reused: 1
extra: timeout
--- error_log
lua tcp socket queue connect operation for connection pool "legacy_replaces_idle"
--- no_error_log
[error]



=== TEST 91: conn queuing: a fast shutdown frees pools with queued connects and idle connections
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local ffi = require "ffi"
            pcall(ffi.cdef, [[
                int getpid(void);
                int kill(int pid, int sig);
            ]])

            -- collected by lua_close(), which runs after the pools are freed
            local marker = newproxy(true)
            getmetatable(marker).__gc = function()
                ngx.log(ngx.WARN, "Lua VM closed after the pool cleanup")
            end
            package.loaded.fast_shutdown_marker = marker

            local port = ngx.var.port
            local opts = {pool = "fast_shutdown", pool_size = 1, backlog = 2}

            -- another pool keeps an idle connection until the shutdown
            local idle = assert(ngx.socket.connect("127.0.0.1", port,
                                                   {pool = "fast_shutdown_idle",
                                                    pool_size = 1, backlog = 1}))
            assert(idle:setkeepalive())

            assert(ngx.timer.at(0, function()
                local holder = assert(ngx.socket.connect("127.0.0.1", port,
                                                         opts))
                for _ = 1, 2 do
                    ngx.thread.spawn(function()
                        local sock = ngx.socket.tcp()
                        sock:settimeout(10000)
                        sock:connect("127.0.0.1", port, opts)
                    end)
                end

                ngx.sleep(10)
                holder:close()
            end))

            -- let the timer queue its connects
            ngx.sleep(0.05)
            ngx.say("ok")
            ngx.eof()

            -- the worker exits at once, with both connects still queued
            ffi.C.kill(ffi.C.getpid(), 15)
        }
    }
--- request
GET /t
--- response_body
ok
--- error_log
lua tcp socket keepalive: free connection pool
Lua VM closed after the pool cleanup
--- no_error_log
[alert]
--- wait: 0.2



=== TEST 92: conn queuing: a waiter resumed with an empty slot reuses a connection cached before it runs
--- config
    location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        lua_socket_log_errors off;

        content_by_lua_block {
            local port = ngx.var.port
            local opts = {pool = "empty_slot_reuse", pool_size = 2, backlog = 1}
            local a = assert(ngx.socket.connect("127.0.0.1", port, opts))
            local b = assert(ngx.socket.connect("127.0.0.1", port, opts))

            local w = ngx.thread.spawn(function()
                local sock = ngx.socket.tcp()
                sock:settimeout(1000)
                assert(sock:connect("127.0.0.1", port, opts))
                return sock
            end)

            -- a frees an empty slot for w; before w runs, b goes back to the
            -- pool with nobody waiting any more
            assert(a:close())
            assert(b:setkeepalive())

            local ok, sock = ngx.thread.wait(w)
            assert(ok, sock)
            ngx.say("w: reused ", sock:getreusedtimes())

            -- w gave its spare slot back: one more connection fits
            local c = ngx.socket.tcp()
            c:settimeout(100)
            local ok, err = c:connect("127.0.0.1", port, opts)
            ngx.say("c: ", ok and "reused " .. c:getreusedtimes() or err)

            local extra = ngx.socket.tcp()
            extra:settimeout(50)
            local connected, err = extra:connect("127.0.0.1", port, opts)
            ngx.say("extra: ", connected or err)
            if connected then
                extra:close()
            end

            if ok then
                c:close()
            end

            sock:close()
        }
    }
--- request
GET /t
--- response_body
w: reused 1
c: reused 0
extra: timeout
--- error_log
lua tcp socket resumed connect operation reuses an idle connection, releasing its spare slot
--- no_error_log
[error]
