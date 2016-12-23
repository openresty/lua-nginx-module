# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#no_nginx_manager();
log_level('warn');
#master_on();

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 18);
#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: duplicate rewrite directives
--- config
    location /t {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "first rewrite") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "second rewrite") }
        rewrite_by_lua_block { ngx.print("Hello, Lua!\n") }
        content_by_lua_block { return }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- error_log
first rewrite
second rewrite



=== TEST 2: the first return status == 200
--- config
    location /t {
        rewrite_by_lua_block { ngx.print("Hello, Lua!\n") }
        rewrite_by_lua_block { ngx.print("Hello, again Lua!\n") }
        content_by_lua_block { return }
    }
--- request
GET /t
--- response_body
Hello, Lua!



=== TEST 3: mix three different styles
--- config
    location /t {
        rewrite_by_lua ' ngx.log(ngx.ERR, "rewrite_by_lua") ';
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite_by_lua_block") }
        rewrite_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
ngx.log(ngx.ERR, "rewrite_by_lua_file")
ngx.print("Hello, Lua!\n")
--- request
GET /t
--- response_body
Hello, Lua!
--- error_log
rewrite_by_lua
rewrite_by_lua_block
rewrite_by_lua_file



=== TEST 4: rewrite directives max limit is 10
--- config
    location /t {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        content_by_lua_block { return }
    }
--- request
GET /t
--- must_die
--- error_log
max rewrite directives limit to 10



=== TEST 5: the first return status > 200
--- config
    location /t {
        rewrite_by_lua_block { ngx.exit(503) }
        rewrite_by_lua_block { ngx.print("Hello, again Lua!\n") }
        content_by_lua_block { return }
    }
--- request
GET /t
--- error_code: 503



=== TEST 6: the first return status == 0
--- config
    location /t {
        rewrite_by_lua_block {
          ngx.log(ngx.ERR, "rewrite_by_lua_block first")
          ngx.exit(0)
        }
        rewrite_by_lua_block { ngx.print("Hello, Lua!\n") }
        content_by_lua_block { return }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- error_log
rewrite_by_lua_block first



=== TEST 7:
--- config
    location /t {
        rewrite_by_lua_block {
            ngx.log(ngx.ERR, "first rewrite before sleep")
            ngx.sleep(0.001)
            ngx.log(ngx.ERR, "first rewrite after sleep")
            ngx.sleep(0.001)
        }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "second rewrite") }
        rewrite_by_lua_block { ngx.print("Hello, Lua!\n") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- error_log
first rewrite before sleep
first rewrite after sleep
second rewrite



=== TEST 8: yield by ngx.location.capture
--- config
    location = /internal {
        echo "internal";
    }
    location /t {
        rewrite_by_lua_block {
            ngx.log(ngx.ERR, "first rewrite before sleep")

            local res = ngx.location.capture("/internal")
            ngx.log(ngx.ERR, "status:", res.status, " body:", res.body)

            ngx.log(ngx.ERR, "first rewrite after sleep")
        }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "second rewrite") }
        rewrite_by_lua_block { ngx.print("Hello, Lua!\n") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- error_log
first rewrite before sleep
status:200 body:internal
first rewrite after sleep
second rewrite



=== TEST 9: rewrite directives at different scopes (server + location)
--- config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at server") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at server") }

    location = /t {
        echo "Hello /t";
    }

    location /t2 {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.print("Hello t2") }
    }
--- request
GET /t
--- response_body
Hello /t
--- no_error_log
rewrite 1 at location
--- error_log
rewrite 1 at server
rewrite 2 at server



=== TEST 10: rewrite directives at different scopes (server + location)
--- config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at server") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at server") }

    location = /t {
        echo "Hello /t";
    }

    location /t2 {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.print("Hello /t2\n") }
    }
--- request
GET /t2
--- response_body
Hello /t2
--- no_error_log
rewrite 1 at server
rewrite 2 at server
--- error_log
rewrite 1 at location



=== TEST 11: rewrite directives at different scopes (http + location)
--- http_config
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at http") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 2 at http") }
--- config
    location = /t {
        echo "Hello /t";
    }

    location /t2 {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite 1 at location") }
        rewrite_by_lua_block { ngx.print("Hello /t2\n") }
    }
--- request
GET /t
--- response_body
Hello /t
--- no_error_log
rewrite 1 at location
--- error_log
rewrite 1 at http
rewrite 2 at http



=== TEST 12: rewrite directives at different scopes (http + server)
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
--- no_error_log
rewrite 1 at http
rewrite 2 at http
--- error_log
rewrite 1 at server
rewrite 2 at server



=== TEST 13: rewrite directives at different scopes (http + server + location)
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
--- error_log
rewrite 1 at location
rewrite 2 at location
--- no_error_log
rewrite 1 at http
rewrite 2 at http
rewrite 1 at server
rewrite 2 at server
