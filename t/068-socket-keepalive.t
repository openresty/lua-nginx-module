# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 5);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

no_long_string();
#no_diff();
#log_level 'warn';

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
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
--- request
GET /t
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

    local req = "flush_all\r\n"

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
--- response_body_like
^connected: 1, reused: \d+
request sent: 11
received: OK
connected: 1, reused: [1-9]\d*
request sent: 11
received: OK
--- no_error_log eval
["[error]",
"lua socket keepalive: free connection pool for "]
--- error_log
lua socket get keepalive peer: using connection



=== TEST 2: free up the whole connection pool if no active connections
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
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

    local req = "flush_all\r\n"

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
--- response_body_like
^connected: 1, reused: \d+
request sent: 11
received: OK
connected: 1, reused: [1-9]\d*
request sent: 11
received: OK
--- no_error_log
[error]
--- error_log eval
["lua socket get keepalive peer: using connection",
"lua socket keepalive: free connection pool for "]

