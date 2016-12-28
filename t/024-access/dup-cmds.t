# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#no_nginx_manager();
log_level('warn');
#master_on();

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 - 3);
#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: duplicate access directives
--- config
    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1") }
        access_by_lua_block { ngx.log(ngx.ERR, "access 2") }
        access_by_lua_block { ngx.print("Hello, Lua!\n") }
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



=== TEST 2: the first return status == 200
--- config
    location /t {
        access_by_lua_block { ngx.print("Hello, Lua!\n") }
        access_by_lua_block { ngx.print("Hello, again Lua!\n") }
    }
--- request
GET /t
--- response_body
Hello, Lua!



=== TEST 3: mix three different styles
--- config
    location /t {
        access_by_lua ' ngx.log(ngx.ERR, "access by lua") ';
        access_by_lua_block { ngx.log(ngx.ERR, "access by block") }
        access_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
ngx.log(ngx.ERR, "access by file")
ngx.print("Hello, Lua!\n")
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



=== TEST 4: access directives max limit is 10
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



=== TEST 5: the first return status > 200
--- config
    location /t {
        access_by_lua_block { ngx.exit(503) }
        access_by_lua_block { ngx.print("Hello, again Lua!\n") }
    }
--- request
GET /t
--- error_code: 503



=== TEST 6: the first return status == 0
--- config
    location /t {
        access_by_lua_block {
          ngx.log(ngx.ERR, "access_by_lua_block first")
          ngx.exit(0)
        }
        access_by_lua_block { ngx.print("Hello, Lua!\n") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/access_by_lua_block first/
--- grep_error_log_out
access_by_lua_block first



=== TEST 7: multiple yield by ngx.sleep
--- config
    location /t {
        access_by_lua_block {
            ngx.sleep(0.001)
            ngx.log(ngx.ERR, "first access before sleep")
            ngx.sleep(0.001)
            ngx.log(ngx.ERR, "first access after sleep")
            ngx.sleep(0.001)
        }
        access_by_lua_block { ngx.log(ngx.ERR, "second access") }
        access_by_lua_block { ngx.print("Hello, Lua!\n") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/first access (before|after) sleep|second access/
--- grep_error_log_out
first access before sleep
first access after sleep
second access



=== TEST 8: multiple yield by ngx.location.capture
--- config
    location = /internal {
        echo "internal";
    }
    location /t {
        access_by_lua_block {
            ngx.log(ngx.ERR, "first access before capture")

            local res = ngx.location.capture("/internal")
            ngx.log(ngx.ERR, "status:", res.status, " body:", res.body)

            ngx.location.capture("/internal")

            ngx.log(ngx.ERR, "first access after capture")
        }
        access_by_lua_block { ngx.log(ngx.ERR, "second access") }
        access_by_lua_block { ngx.print("Hello, Lua!\n") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/first access before capture|status:200 body:internal|first access after capture|second access/
--- grep_error_log_out
first access before capture
status:200 body:internal
first access after capture
second access



=== TEST 9: yield by ngx.req.get_body_data()
--- config
    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1") }
        access_by_lua_block {
            ngx.req.read_body()

            local data = ngx.req.get_body_data()
            ngx.say("request body:", data)

            ngx.log(ngx.ERR, "access 2")
        }
    }
--- request
POST /t
hi
--- response_body
request body:hi
--- grep_error_log eval
qr/access \d/
--- grep_error_log_out
access 1
access 2



=== TEST 10: access directives at different scopes (server + location)
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at server") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at server") }

    location = /t {
        echo "Hello /t";
    }

    location /t2 {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1 at location") }
        access_by_lua_block { ngx.print("Hello t2") }
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/access \d at (server|location)/
--- grep_error_log_out
access 1 at server
access 2 at server



=== TEST 11: access directives at different scopes (server + location)
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at server") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at server") }

    location = /t {
        echo "Hello /t";
    }

    location /t2 {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1 at location") }
        access_by_lua_block { ngx.print("Hello /t2\n") }
    }
--- request
GET /t2
--- response_body
Hello /t2
--- grep_error_log eval
qr/access \d at (location|server)/
--- grep_error_log_out
access 1 at location



=== TEST 12: access directives at different scopes (http + location)
--- http_config
    access_by_lua_block { ngx.log(ngx.ERR, "access 1 at http") }
    access_by_lua_block { ngx.log(ngx.ERR, "access 2 at http") }
--- config
    location = /t {
        echo "Hello /t";
    }

    location /t2 {
        access_by_lua_block { ngx.log(ngx.ERR, "access 1 at location") }
        access_by_lua_block { ngx.print("Hello /t2\n") }
    }
--- request
GET /t
--- response_body
Hello /t
--- grep_error_log eval
qr/access \d at (http|location)/
--- grep_error_log_out
access 1 at http
access 2 at http



=== TEST 13: access directives at different scopes (http + server)
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
qr/access \d at (server|http)/
--- grep_error_log_out
access 1 at server
access 2 at server



=== TEST 14: access directives at different scopes (http + server + location)
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
qr/access \d at (server|http|location)/
--- grep_error_log_out
access 1 at location
access 2 at location
