# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 7);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: simple logging
--- http_config
    upstream backend {
        server 0.0.0.0;
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
qr{connect\(\) failed .*?, upstream: "http://0\.0\.0\.0:80/t"},
]
--- no_error_log
[warn]



=== TEST 2: set current peer (separate addr and port)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lua/?.lua;;";

    upstream backend {
        server 0.0.0.0;
        balancer_by_lua_block {
            print("hello from balancer by lua!")
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.3", 12345))
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
qr{connect\(\) failed .*?, upstream: "http://127\.0\.0\.3:12345/t"},
]
--- no_error_log
[warn]



=== TEST 3: set current peer & next upstream (3 tries)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lua/?.lua;;";

    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504 http_403 http_404;
    proxy_next_upstream_tries 10;

    upstream backend {
        server 0.0.0.0;
        balancer_by_lua_block {
            print("hello from balancer by lua!")
            local b = require "ngx.balancer"
            if not ngx.ctx.tries then
                ngx.ctx.tries = 0
            end

            if ngx.ctx.tries < 2 then
                local ok, err = b.set_more_tries(1)
                if not ok then
                    return error("failed to set more tries: ", err)
                elseif err then
                    ngx.log(ngx.WARN, "set more tries: ", err)
                end
            end
            ngx.ctx.tries = ngx.ctx.tries + 1
            assert(b.set_current_peer("127.0.0.3", 12345))
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
--- grep_error_log eval: qr{connect\(\) failed .*, upstream: "http://.*?"}
--- grep_error_log_out eval
qr#^(?:connect\(\) failed .*?, upstream: "http://127.0.0.3:12345/t"\n){3}$#
--- no_error_log
[warn]



=== TEST 4: set current peer & next upstream (no retries)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lua/?.lua;;";

    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504 http_403 http_404;
    proxy_next_upstream_tries 10;

    upstream backend {
        server 0.0.0.0;
        balancer_by_lua_block {
            print("hello from balancer by lua!")
            local b = require "ngx.balancer"
            if not ngx.ctx.tries then
                ngx.ctx.tries = 0
            end

            ngx.ctx.tries = ngx.ctx.tries + 1
            assert(b.set_current_peer("127.0.0.3", 12345))
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
--- grep_error_log eval: qr{connect\(\) failed .*, upstream: "http://.*?"}
--- grep_error_log_out eval
qr#^(?:connect\(\) failed .*?, upstream: "http://127.0.0.3:12345/t"\n){1}$#
--- no_error_log
[warn]



=== TEST 5: set current peer & next upstream (3 tries exceeding the limit)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lua/?.lua;;";

    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504 http_403 http_404;
    proxy_next_upstream_tries 2;

    upstream backend {
        server 0.0.0.0;
        balancer_by_lua_block {
            local b = require "ngx.balancer"

            if not ngx.ctx.tries then
                ngx.ctx.tries = 0
            end

            if ngx.ctx.tries < 2 then
                local ok, err = b.set_more_tries(1)
                if not ok then
                    return error("failed to set more tries: ", err)
                elseif err then
                    ngx.log(ngx.WARN, "set more tries: ", err)
                end
            end
            ngx.ctx.tries = ngx.ctx.tries + 1
            assert(b.set_current_peer("127.0.0.3", 12345))
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
--- grep_error_log eval: qr{connect\(\) failed .*, upstream: "http://.*?"}
--- grep_error_log_out eval
qr#^(?:connect\(\) failed .*?, upstream: "http://127.0.0.3:12345/t"\n){2}$#
--- error_log
set more tries: reduced tries due to limit



=== TEST 6: get last peer failure status (404)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lua/?.lua;;";

    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504 http_403 http_404;
    proxy_next_upstream_tries 10;

    upstream backend {
        server 0.0.0.0;
        balancer_by_lua_block {
            local b = require "ngx.balancer"

            local state, status = b.get_last_failure()
            print("last peer failure: ", state, " ", status)

            if not ngx.ctx.tries then
                ngx.ctx.tries = 0
            end

            if ngx.ctx.tries < 2 then
                local ok, err = b.set_more_tries(1)
                if not ok then
                    return error("failed to set more tries: ", err)
                elseif err then
                    ngx.log(ngx.WARN, "set more tries: ", err)
                end
            end
            ngx.ctx.tries = ngx.ctx.tries + 1
            assert(b.set_current_peer("127.0.0.1", tonumber(ngx.var.server_port)))
        }
    }
--- config
    location = /t {
        proxy_pass http://backend/back;
    }

    location = /back {
        return 404;
    }
--- request
    GET /t
--- response_body_like: 404 Not Found
--- error_code: 404
--- grep_error_log eval: qr{last peer failure: \S+ \S+}
--- grep_error_log_out
last peer failure: nil nil
last peer failure: next 404
last peer failure: next 404

--- no_error_log
[warn]



=== TEST 7: get last peer failure status (500)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lua/?.lua;;";

    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504 http_403 http_404;
    proxy_next_upstream_tries 10;

    upstream backend {
        server 0.0.0.0;
        balancer_by_lua_block {
            local b = require "ngx.balancer"

            local state, status = b.get_last_failure()
            print("last peer failure: ", state, " ", status)

            if not ngx.ctx.tries then
                ngx.ctx.tries = 0
            end

            if ngx.ctx.tries < 2 then
                local ok, err = b.set_more_tries(1)
                if not ok then
                    return error("failed to set more tries: ", err)
                elseif err then
                    ngx.log(ngx.WARN, "set more tries: ", err)
                end
            end
            ngx.ctx.tries = ngx.ctx.tries + 1
            assert(b.set_current_peer("127.0.0.1", tonumber(ngx.var.server_port)))
        }
    }
--- config
    location = /t {
        proxy_pass http://backend/back;
    }

    location = /back {
        return 500;
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- grep_error_log eval: qr{last peer failure: \S+ \S+}
--- grep_error_log_out
last peer failure: nil nil
last peer failure: failed 500
last peer failure: failed 500

--- no_error_log
[warn]



=== TEST 8: get last peer failure status (connect failed)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lua/?.lua;;";

    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504 http_403 http_404;
    proxy_next_upstream_tries 10;

    upstream backend {
        server 0.0.0.0;
        balancer_by_lua_block {
            local b = require "ngx.balancer"

            local state, status = b.get_last_failure()
            print("last peer failure: ", state, " ", status)

            if not ngx.ctx.tries then
                ngx.ctx.tries = 0
            end

            if ngx.ctx.tries < 2 then
                local ok, err = b.set_more_tries(1)
                if not ok then
                    return error("failed to set more tries: ", err)
                elseif err then
                    ngx.log(ngx.WARN, "set more tries: ", err)
                end
            end
            ngx.ctx.tries = ngx.ctx.tries + 1
            assert(b.set_current_peer("127.0.0.3", 12345))
        }
    }
--- config
    location = /t {
        proxy_pass http://backend/back;
    }

    location = /back {
        return 404;
    }
--- request
    GET /t
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- grep_error_log eval: qr{last peer failure: \S+ \S+}
--- grep_error_log_out
last peer failure: nil nil
last peer failure: failed 502
last peer failure: failed 502

--- no_error_log
[warn]



=== TEST 9: exit 403
--- http_config
    upstream backend {
        server 0.0.0.0;
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
qr{connect\(\) failed .*?, upstream: "http://0\.0\.0\.0:80/t"},
]



=== TEST 10: exit OK
--- http_config
    upstream backend {
        server 0.0.0.0;
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
qr{connect\(\) failed .*?, upstream: "http://0\.0\.0\.0:80/t"},
]
--- no_error_log
[warn]



=== TEST 11: ngx.var works
--- http_config
    upstream backend {
        server 0.0.0.0;
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
--- error_log
1: variable foo = 32
2: variable foo = 33
--- no_error_log
[warn]



=== TEST 12: ngx.req.get_headers works
--- http_config
    upstream backend {
        server 0.0.0.0;
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
--- error_log
header foo: bar
--- no_error_log
[warn]



=== TEST 13: ngx.req.get_uri_args() works
--- http_config
    upstream backend {
        server 0.0.0.0;
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
--- error_log
arg foo: bar
--- no_error_log
[warn]



=== TEST 14: ngx.req.get_method() works
--- http_config
    upstream backend {
        server 0.0.0.0;
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
--- error_log
method: GET
--- no_error_log
[warn]



=== TEST 15: simple logging (by_lua_file)
--- http_config
    upstream backend {
        server 0.0.0.0;
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
qr{connect\(\) failed .*?, upstream: "http://0\.0\.0\.0:80/t"},
]
--- no_error_log
[warn]



=== TEST 16: set current peer (port embedded in addr)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lua/?.lua;;";

    upstream backend {
        server 0.0.0.0;
        balancer_by_lua_block {
            print("hello from balancer by lua!")
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.3:12345"))
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
qr{connect\(\) failed .*?, upstream: "http://127\.0\.0\.3:12345/t"},
]
--- no_error_log
[warn]
