# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 5 + 7);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;
$ENV{TEST_NOT_EXIST_IP} ||= '8.8.8.8';
$ENV{TEST_INVALID_IP} ||= '127.0.0.1:8899';

$ENV{LUA_PATH} ||=
    '/usr/local/openresty-debug/lualib/?.lua;/usr/local/openresty/lualib/?.lua;;';

no_long_string();
#no_diff();

#log_level 'warn';
log_level 'debug';

no_shuffle();

run_tests();

__DATA__

=== TEST 1: upstream sockets bind 127.0.0.1
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local ip = "127.0.0.1"
            local port = ngx.var.port

            local sock = ngx.socket.tcp()
            local ok, err = sock:bind(ip)
            if not ok then
                ngx.say("failed to bind", err)
                return
            end

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local bytes, err = sock:send("GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n")
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent")

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, err = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response")	
            local remote_ip = string.match(data, "(bind: %d+%.%d+%.%d+%.%d+)")
            ngx.say(remote_ip)

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';
    }

    location /foo {
        echo bind: $remote_addr
    }

    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent
received response
bind: 127.0.0.1
done
--- no_error_log
["[error]",
"bind(127.0.0.1) failed"]
--- error_log eval
"lua tcp socket bind ip: 127.0.0.1"



=== TEST 2: upstream sockets bind server ip, not 127.0.0.1
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local ip = $TEST_NGINX_SERVER_IP
            local port = ngx.var.port

            local sock = ngx.socket.tcp()
            local ok, err = sock:bind(ip)
            if not ok then
                ngx.say("failed to bind", err)
                return
            end

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local bytes, err = sock:send("GET /foo HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: keepalive\\r\\n\\r\\n")
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent")

            local reader = sock:receiveuntil("\\r\\n0\\r\\n\\r\\n")
            local data, err = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response")	
            local remote_ip = string.match(data, "(bind: %d+%.%d+%.%d+%.%d+)")
            ngx.say(remote_ip)

            ngx.location.capture("/sleep")

            ngx.say("done")
        ';
    }

    location /foo {
        echo bind: $remote_addr
    }
    location /sleep {
        echo_sleep 1;
    }
--- request
GET /t
--- response_body
connected: 1
request sent
received response
bind: $ENV{TEST_NGINX_SERVER_IP}
done
--- no_error_log
["[error]",
"bind(127.0.0.1) failed"]
--- error_log eval
"lua tcp socket bind ip: $ENV{TEST_NGINX_SERVER_IP}"



=== TEST 3: add setkeepalive
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local test = require "test"
            test.go()
            test.go()
        ';
    }
--- user_files
>>> test.lua
module("test", package.seeall)

function go()
    local ip = "127.0.0.1"
    local port = ngx.var.port

    local sock = ngx.socket.tcp()
    local ok, err = sock:bind(ip)
    if not ok then
        ngx.say("failed to bind", err)
        return
    end

    ngx.say("bind: ", ip)

    local ok, err = sock:connect("127.0.0.1", port)
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
bind: 127.0.0.1
connected: 1
bind: 127.0.0.1
connected: 1
--- no_error_log
["[error]",
"bind(127.0.0.1) failed"]
--- error_log eval
"lua tcp socket bind ip: 127.0.0.1"



=== TEST 4: upstream sockets bind not exist ip
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local ip = $TEST_NOT_EXIST_IP
            local port = ngx.var.port

            local sock = ngx.socket.tcp()
            local ok, err = sock:bind(ip)
            if not ok then
                ngx.say("failed to bind", err)
                return
            end

            ngx.say("bind: ", ip)

            local ok, err = sock:connect("127.0.0.1", port)
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
bind: 8.8.8.8
failed to connect: cannot assign requested address
--- error_log
["bind(8.8.8.8) failed",
"lua tcp socket bind ip: 8.8.8.8"



=== TEST 5: upstream sockets bind invalid ip
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua '
            local ip = $TEST_INVALID_IP
            local port = ngx.var.port

            local sock = ngx.socket.tcp()
            local ok, err = sock:bind(ip)
            if not ok then
                ngx.say("failed to bind: ", err)
                return
            end

            ngx.say("bind: ", ip)

            local ok, err = sock:connect("127.0.0.1", port)
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
failed to bind: bad ip: "127.0.0.1:8899"

