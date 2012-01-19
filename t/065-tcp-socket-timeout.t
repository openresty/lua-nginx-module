# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 5);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

no_long_string();
no_diff();
run_tests();

__DATA__

=== TEST 1: lua_socket_connect_timeout only
--- config
    server_tokens off;
    lua_socket_connect_timeout 100ms;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("www.taobao.com", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- timeout: 1
--- error_log
lua socket connect timeout: 100



=== TEST 2: sock:settimeout() overrides lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 60s;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(150)
            local ok, err = sock:connect("www.taobao.com", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- timeout: 1
--- error_log
lua socket connect timeout: 150



=== TEST 3: sock:settimeout(nil) does not override lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(nil)
            local ok, err = sock:connect("www.taobao.com", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- timeout: 1
--- error_log
lua socket connect timeout: 102



=== TEST 4: sock:settimeout(0) does not override lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(0)
            local ok, err = sock:connect("www.taobao.com", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- timeout: 1
--- error_log
lua socket connect timeout: 102



=== TEST 5: sock:settimeout(-1) does not override lua_socket_connect_timeout
--- config
    server_tokens off;
    lua_socket_connect_timeout 102ms;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            sock:settimeout(-1)
            local ok, err = sock:connect("www.taobao.com", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: timeout
--- timeout: 1
--- error_log
lua socket connect timeout: 102



=== TEST 6: lua_socket_read_timeout only
--- config
    server_tokens off;
    lua_socket_read_timeout 100ms;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local line
            line, err = sock:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- timeout: 1
--- error_log eval
["lua socket read timeout: 100",
"lua socket connect timeout: 60000"]



=== TEST 7: sock:settimeout() overrides lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 60s;
    #resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(150)

            local line
            line, err = sock:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- timeout: 1
--- error_log eval
["lua socket connect timeout: 60000",
"lua socket read timeout: 150"]



=== TEST 8: sock:settimeout(nil) does not override lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(nil)

            local line
            line, err = sock:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- timeout: 1
--- error_log eval
["lua socket connect timeout: 60000",
"lua socket read timeout: 102"]



=== TEST 9: sock:settimeout(0) does not override lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(0)

            local line
            line, err = sock:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)
            end

        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- timeout: 1
--- error_log eval
["lua socket connect timeout: 60000",
"lua socket read timeout: 102"]



=== TEST 10: sock:settimeout(-1) does not override lua_socket_read_timeout
--- config
    server_tokens off;
    lua_socket_read_timeout 102ms;
    #resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            sock:settimeout(-1)

            local line
            line, err = sock:receive()
            if line then
                ngx.say("received: ", line)
            else
                ngx.say("failed to receive: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
failed to receive: timeout
--- timeout: 1
--- error_log eval
["lua socket read timeout: 102",
"lua socket connect timeout: 60000"]

