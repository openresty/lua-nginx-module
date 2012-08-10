# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: log socket errors off
--- config
    location /t {
        lua_socket_connect_timeout 1s;
        lua_log_socket_errors off;
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("8.8.8.8", 80) 
            ngx.say(err)
        ';
    }
--- request
GET /t
--- response_body
timeout
--- no_error_log
[error]



=== TEST 2: log socket errors on
--- config
    location /t {
        lua_socket_connect_timeout 1s;
        lua_log_socket_errors on;
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("8.8.8.8", 80) 
            ngx.say(err)
        ';
    }
--- request
GET /t
--- response_body
timeout
--- error_log
lua tcp socket connect timed out



