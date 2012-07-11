# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => blocks() * 2 * repeat_each();

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;
#$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

$ENV{LUA_PATH} ||=
    '/usr/local/openresty-debug/lualib/?.lua;/usr/local/openresty/lualib/?.lua;;';

no_long_string();
#no_diff();
#log_level 'warn';

no_shuffle();

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local port = ngx.var.port
            for i=1,2 do
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("127.0.0.1", port, { pool = "test" })
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
        ';
    }
--- request
GET /t
--- response_body_like
^connected: 1, reused: \d+
connected: 1, reused: [1-9]\d*

=== TEST 2: two pools
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local port = ngx.var.port
            function socktest(port, pool)
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("127.0.0.1", port, { pool = pool })
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
            for i=1,10 do
                socktest(port, "one")
                socktest(port, "two")
            end
        ';
    }
--- request
GET /t
--- response_body_like
(connected: 1, reused: \d+\s+)*

=== TEST 3: unix socket
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        default_type 'text/plain';
    }
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local port = ngx.var.port
            for i=1,2 do
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock", nil, { pool = "nginx.sock" })
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
        ';
    }
--- request
GET /t
--- response_body_like
^connected: 1, reused: \d+
connected: 1, reused: [1-9]\d*


=== TEST 2: unix socket - two pools
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        default_type 'text/plain';
    }
--- config
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;
        content_by_lua '
            local port = ngx.var.port
            function socktest(port, pool)
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock", nil, { pool = pool })
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
            for i=1,10 do
                socktest(port, "one")
                socktest(port, "two")
            end
        ';
    }
--- request
GET /t
--- response_body_like
(connected: 1, reused: \d+\s+)*


