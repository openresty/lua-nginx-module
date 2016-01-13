# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 8);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: simple logging
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("hello from balancer by lua!")
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
'[lua] balancer_by_lua:2: hello from balancer by lua! while connecting to upstream,',
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"},
]
--- no_error_log
[warn]



=== TEST 2: exit 403
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("hello from balancer by lua!")
            ngx.exit(403)
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
[lua] balancer_by_lua:2: hello from balancer by lua! while connecting to upstream,
--- no_error_log eval
[
'[warn]',
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"},
]



=== TEST 3: exit OK
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("hello from balancer by lua!")
            ngx.exit(ngx.OK)
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
'[lua] balancer_by_lua:2: hello from balancer by lua! while connecting to upstream,',
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"},
]
--- no_error_log
[warn]



=== TEST 4: ngx.var works
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("1: variable foo = ", ngx.var.foo)
            ngx.var.foo = tonumber(ngx.var.foo) + 1
            print("2: variable foo = ", ngx.var.foo)
        }
    }
--- config
    location = /t {
        set $foo 32;
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
"1: variable foo = 32",
"2: variable foo = 33",
qr/\[crit\] .* connect\(\) .*? failed/,
]
--- no_error_log
[warn]



=== TEST 5: ngx.req.get_headers works
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("header foo: ", ngx.req.get_headers()["foo"])
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- more_headers
Foo: bar
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
"header foo: bar",
qr/\[crit\] .* connect\(\) .*? failed/,
]
--- no_error_log
[warn]



=== TEST 6: ngx.req.get_uri_args() works
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("arg foo: ", ngx.req.get_uri_args()["foo"])
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t?baz=blah&foo=bar
--- more_headers
Foo: bar
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
["arg foo: bar",
qr/\[crit\] .* connect\(\) .*? failed/,
]
--- no_error_log
[warn]



=== TEST 7: ngx.req.get_method() works
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("method: ", ngx.req.get_method())
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- more_headers
Foo: bar
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
"method: GET",
qr/\[crit\] .* connect\(\) .*? failed/,
]
--- no_error_log
[warn]



=== TEST 8: simple logging (by_lua_file)
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_file html/a.lua;
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- user_files
>>> a.lua
print("hello from balancer by lua!")
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
[
'[lua] a.lua:1: hello from balancer by lua! while connecting to upstream,',
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"},
]
--- no_error_log
[warn]



=== TEST 9: cosockets are disabled
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            local sock, err = ngx.socket.tcp()
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/\[error\] .*? failed to run balancer_by_lua\*: balancer_by_lua:2: API disabled in the context of balancer_by_lua\*/



=== TEST 10: ngx.sleep is disabled
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            ngx.sleep(0.1)
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/\[error\] .*? failed to run balancer_by_lua\*: balancer_by_lua:2: API disabled in the context of balancer_by_lua\*/



=== TEST 11: get_phase
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            print("I am in phase ", ngx.get_phase())
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- grep_error_log eval: qr/I am in phase \w+/
--- grep_error_log_out
I am in phase balancer
--- error_log eval
qr{\[crit\] .*? connect\(\) to 0\.0\.0\.1:80 failed .*?, upstream: "http://0\.0\.0\.1:80/t"}
--- no_error_log
[error]
