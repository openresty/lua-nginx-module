# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#no_nginx_manager();
#log_level('warn');
#master_on();

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 - 1);
#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: duplicate rewrite directives
--- config
    location /t {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2") }
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/rewrite \d/
--- grep_error_log_out
rewrite 1
rewrite 2



=== TEST 2: the first return status == 200
--- config
    location /t {
        rewrite_by_lua_block { ngx.say("Hello, Lua!") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite") }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
Hello, Lua!



=== TEST 3: mix three different styles
--- config
    location /t {
        rewrite_by_lua ' ngx.log(ngx.ERR, "rewrite by lua") ';
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite by block") }
        rewrite_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
ngx.log(ngx.ERR, "rewrite by file")
ngx.say("Hello, Lua!")
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/rewrite by \w+/
--- grep_error_log_out
rewrite by lua
rewrite by block
rewrite by file



=== TEST 4: the number of rewrite_by_lua* directives exceeds 10
--- config
    location /t {
        rewrite_by_lua_block { return }
        rewrite_by_lua_block { return }
        rewrite_by_lua_block { return }
        rewrite_by_lua_block { return }
        rewrite_by_lua_block { return }
        rewrite_by_lua_block { return }
        rewrite_by_lua_block { return }
        rewrite_by_lua_block { return }
        rewrite_by_lua_block { return }
        rewrite_by_lua_block { return }
        rewrite_by_lua_block { return }
        content_by_lua_block { return }
    }
--- request
GET /t
--- no_error_log
[error]
--- must_die
--- error_log eval
qr/\[emerg\] .*? the number of rewrite_by_lua\* directives exceeds 10/



=== TEST 5: the first return status > 200
--- config
    location /t {
        rewrite_by_lua_block { ngx.exit(503) }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite") }
    }
--- request
GET /t
--- error_code: 503
--- no_error_log
[error]



=== TEST 6: the first return status == 0
--- config
    location /t {
        rewrite_by_lua_block {
          ngx.log(ngx.ERR, "rewrite 1")
          ngx.exit(0)
        }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2") }
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/rewrite \d/
--- grep_error_log_out
rewrite 1
rewrite 2



=== TEST 7: multiple yields by ngx.sleep
--- config
    location /t {
        rewrite_by_lua_block {
            ngx.log(ngx.ERR, "rewrite 1 before sleep")
            ngx.sleep(0.001)
            ngx.log(ngx.ERR, "rewrite 1 after sleep")
        }

        rewrite_by_lua_block {
            ngx.sleep(0.001)
            ngx.log(ngx.ERR, "rewrite 2")
            ngx.sleep(0.001)
        }

        rewrite_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/rewrite \d (before|after) sleep|rewrite \d/
--- grep_error_log_out
rewrite 1 before sleep
rewrite 1 after sleep
rewrite 2



=== TEST 8: yield by ngx.location.capture
--- config
    location /internal {
        echo "internal";
    }
    location /t {
        rewrite_by_lua_block {
            ngx.log(ngx.ERR, "rewrite 1 before capture")

            local res = ngx.location.capture("/internal")
            ngx.log(ngx.ERR, "status:", res.status, " body:", res.body)

            ngx.log(ngx.ERR, "rewrite 1 after capture")
        }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2") }
        rewrite_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/rewrite \d \w+ capture|rewrite \d|status:\d+ body:\w+/
--- grep_error_log_out
rewrite 1 before capture
status:200 body:internal
rewrite 1 after capture
rewrite 2



=== TEST 9: yield by ngx.req.get_body_data()
--- config
    location /t {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1") }
        rewrite_by_lua_block {
            ngx.req.read_body()

            local data = ngx.req.get_body_data()
            ngx.log(ngx.ERR, "request body:", data)
        }
        rewrite_by_lua_block {
            ngx.log(ngx.ERR, "rewrite 2")
            ngx.say("Hello, Lua!")
        }
    }
--- request
POST /t
hi
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/rewrite \d|request body:\w+/
--- grep_error_log_out
rewrite 1
request body:hi
rewrite 2



=== TEST 10: yield by ngx.req.socket()
--- config
    location /t {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1") }
        rewrite_by_lua_block {
            local sock = ngx.req.socket()
            local data = sock:receive(2)
            ngx.log(ngx.ERR, "request body:", data)
        }
        rewrite_by_lua_block {
            ngx.log(ngx.ERR, "rewrite 2")
            ngx.say("Hello, Lua!")
        }
    }
--- request
POST /t
hi
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/rewrite \d|request body:\w+/
--- grep_error_log_out
rewrite 1
request body:hi
rewrite 2



=== TEST 11: multiple directives at different phase: server(Y) + location(N)
--- config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at server") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at server") }

    location = /t {
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/rewrite \d at \w+/
--- grep_error_log_out
rewrite 1 at server
rewrite 2 at server



=== TEST 12: multiple directives at different phase: server(Y) + location(Y)
--- config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at server") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at server") }

    location /t {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at location") }
        echo Hello /t;
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/rewrite \d at \w+/
--- grep_error_log_out
rewrite 1 at location
rewrite 2 at location



=== TEST 13: multiple directives at different phase: http(Y) + location(N)
--- http_config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at http") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at http") }
--- config
    location /t {
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/rewrite \d at \w+/
--- grep_error_log_out
rewrite 1 at http
rewrite 2 at http



=== TEST 14: multiple directives at different phase: http(Y) + location(Y)
--- http_config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at http") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at http") }
--- config
    location /t {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at location") }
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/rewrite \d at \w+/
--- grep_error_log_out
rewrite 1 at location
rewrite 2 at location



=== TEST 15: multiple directives at different phase: http(Y) + server(N)
--- http_config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at http") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at http") }
--- config
    location = /t {
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/rewrite \d at \w+/
--- grep_error_log_out
rewrite 1 at http
rewrite 2 at http



=== TEST 16: multiple directives at different phase: http(Y) + server(Y)
--- http_config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at http") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at http") }
--- config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at server") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at server") }

    location = /t {
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/rewrite \d at \w+/
--- grep_error_log_out
rewrite 1 at server
rewrite 2 at server



=== TEST 17: multiple directives at different phase: http(Y) + server(Y) + location(Y)
--- http_config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at http") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at http") }
--- config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at server") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at server") }

    location = /t {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at location") }
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/rewrite \d at \w+/
--- grep_error_log_out
rewrite 1 at location
rewrite 2 at location
