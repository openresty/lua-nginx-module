# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 - 1);

no_long_string();

run_tests();

__DATA__

=== TEST 1: duplicate access directives
--- config
    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1") }
        access_by_lua_block { ngx.log(ngx.ERR, "access 2") }
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/access \d/
--- grep_error_log_out
access 1
access 2



=== TEST 2: missing ]] (string)
--- config
    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access") }
        access_by_lua_block { ngx.say([[hello, world") }
        access_by_lua_block { ngx.log(ngx.ERR, "access") }
    }
--- request
GET /t
--- no_error_log
[error]
--- must_die
--- error_log eval
qr/\[emerg\] .*? Lua code block missing the closing long bracket "]]" in .*?nginx\.conf:41/



=== TEST 3: return status == 200
--- config
    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1") }
        access_by_lua_block { ngx.say("Hello, Lua!") }
        access_by_lua_block { ngx.log(ngx.ERR, "access 2") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/access \d/
--- grep_error_log_out
access 1



=== TEST 4: return status > 200
--- config
    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1") }
        access_by_lua_block { ngx.exit(503) }
        access_by_lua_block { ngx.log(ngx.ERR, "access 2") }
    }
--- request
GET /t
--- error_code: 503
--- grep_error_log eval
qr/access \d/
--- grep_error_log_out
access 1



=== TEST 5: return status == 0
--- config
    location /t {
        access_by_lua_block {
          ngx.log(ngx.ERR, "access 1")
          ngx.exit(0)
        }
        access_by_lua_block { ngx.log(ngx.ERR, "access 2") }
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/access \d/
--- grep_error_log_out
access 1
access 2



=== TEST 6: mix three different styles
--- config
    location /t {
        access_by_lua ' ngx.log(ngx.ERR, "access by lua") ';
        access_by_lua_block { ngx.log(ngx.ERR, "access by block") }
        access_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
ngx.log(ngx.ERR, "access by file")
ngx.say("Hello, Lua!")
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/access by \w+/
--- grep_error_log_out
access by lua
access by block
access by file



=== TEST 7: the number of access_by_lua* directives exceeds 10
--- config
    location /t {
        access_by_lua_block { return }
        access_by_lua_block { return }
        access_by_lua_block { return }
        access_by_lua_block { return }
        access_by_lua_block { return }
        access_by_lua_block { return }
        access_by_lua_block { return }
        access_by_lua_block { return }
        access_by_lua_block { return }
        access_by_lua_block { return }
        access_by_lua_block { return }
        content_by_lua_block { return }
    }
--- request
GET /t
--- no_error_log
[error]
--- must_die
--- error_log eval
qr/\[emerg\] .*? the number of access_by_lua\* directives exceeds 10/



=== TEST 8: yields by ngx.sleep
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.ERR, "access 1 before sleep")
            ngx.sleep(0.001)
            ngx.log(ngx.ERR, "access 1 after sleep")
        }

        access_by_lua_block {
            ngx.sleep(0.001)
            ngx.log(ngx.ERR, "access 2")
            ngx.sleep(0.001)
        }

        access_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/access \d (before|after) sleep|access \d/
--- grep_error_log_out
access 1 before sleep
access 1 after sleep
access 2



=== TEST 9: yield by ngx.location.capture
--- config
    location /internal {
        echo "internal";
    }
    location /t {
        access_by_lua_block {
            ngx.log(ngx.ERR, "access 1 before capture")

            local res = ngx.location.capture("/internal")
            ngx.log(ngx.ERR, "status:", res.status, " body:", res.body)

            ngx.log(ngx.ERR, "access 1 after capture")
        }
        access_by_lua_block { ngx.log(ngx.ERR, "access 2") }
        access_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/access \d \w+ capture|access \d|status:\d+ body:\w+/
--- grep_error_log_out
access 1 before capture
status:200 body:internal
access 1 after capture
access 2



=== TEST 10: yield by ngx.req.get_body_data()
--- config
    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1") }
        access_by_lua_block {
            ngx.req.read_body()

            local data = ngx.req.get_body_data()
            ngx.log(ngx.ERR, "request body:", data)
        }
        access_by_lua_block {
            ngx.log(ngx.ERR, "access 2")
            ngx.say("Hello, Lua!")
        }
    }
--- request
POST /t
hi
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/access \d|request body:\w+/
--- grep_error_log_out
access 1
request body:hi
access 2



=== TEST 11: yield by ngx.req.socket()
--- config
    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1") }
        access_by_lua_block {
            local sock = ngx.req.socket()
            local data = sock:receive(2)
            ngx.log(ngx.ERR, "request body:", data)
        }
        access_by_lua_block {
            ngx.log(ngx.ERR, "access 2")
            ngx.say("Hello, Lua!")
        }
    }
--- request
POST /t
hi
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/access \d|request body:\w+/
--- grep_error_log_out
access 1
request body:hi
access 2



=== TEST 12: multiple directives at different phase: server(Y) + location(N)
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at server") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at server") }

    location = /t {
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/access \d at \w+/
--- grep_error_log_out
access 1 at server
access 2 at server



=== TEST 13: multiple directives at different phase: server(Y) + location(Y)
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at server") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at server") }

    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1 at location") }
        access_by_lua_block { ngx.log(ngx.ERR, "access 2 at location") }
        echo Hello /t;
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/access \d at \w+/
--- grep_error_log_out
access 1 at location
access 2 at location



=== TEST 14: multiple directives at different phase: http(Y) + location(N)
--- http_config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at http") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at http") }
--- config
    location /t {
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/access \d at \w+/
--- grep_error_log_out
access 1 at http
access 2 at http



=== TEST 15: multiple directives at different phase: http(Y) + location(Y)
--- http_config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at http") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at http") }
--- config
    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1 at location") }
        access_by_lua_block { ngx.log(ngx.ERR, "access 2 at location") }
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/access \d at \w+/
--- grep_error_log_out
access 1 at location
access 2 at location



=== TEST 16: multiple directives at different phase: http(Y) + server(N)
--- http_config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at http") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at http") }
--- config
    location = /t {
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/access \d at \w+/
--- grep_error_log_out
access 1 at http
access 2 at http



=== TEST 17: multiple directives at different phase: http(Y) + server(Y)
--- http_config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at http") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at http") }
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at server") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at server") }

    location = /t {
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/access \d at \w+/
--- grep_error_log_out
access 1 at server
access 2 at server



=== TEST 18: multiple directives at different phase: http(Y) + server(Y) + location(Y)
--- http_config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at http") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at http") }
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at server") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at server") }

    location = /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1 at location") }
        access_by_lua_block { ngx.log(ngx.ERR, "access 2 at location") }
        echo "Hello /t";
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/access \d at \w+/
--- grep_error_log_out
access 1 at location
access 2 at location
