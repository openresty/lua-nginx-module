# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#no_nginx_manager();
log_level('warn');
#master_on();

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);
#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: access + rewrite (location)
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "http 1") }

    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access location 1") }
        access_by_lua_block { ngx.log(ngx.ERR, "access location 2") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite location 1") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite location 2") }
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/(rewrite|access) location \d/
--- grep_error_log_out
rewrite location 1
rewrite location 2
access location 1
access location 2



=== TEST 2: access + rewrite (http)
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "access http 1") }
    access_by_lua_block { ngx.log(ngx.ERR, "access http 2") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite http 1") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite http 2") }

    location /t {
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/(rewrite|access) http \d/
--- grep_error_log_out
rewrite http 1
rewrite http 2
access http 1
access http 2



=== TEST 3: access + rewrite (server)
--- http_config
    access_by_lua_block { ngx.log(ngx.ERR, "access server 1") }
    access_by_lua_block { ngx.log(ngx.ERR, "access server 2") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite server 1") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite server 2") }
--- config
    location /t {
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/(rewrite|access) server \d/
--- grep_error_log_out
rewrite server 1
rewrite server 2
access server 1
access server 2



=== TEST 4: access + rewrite (server+location)
--- http_config
    access_by_lua_block { ngx.log(ngx.ERR, "access server 1") }
    access_by_lua_block { ngx.log(ngx.ERR, "access server 2") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite server 1") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite server 2") }
--- config
    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access location 1") }
        access_by_lua_block { ngx.log(ngx.ERR, "access location 2") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite location 1") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite location 2") }
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/(rewrite|access) (server|location) \d/
--- grep_error_log_out
rewrite location 1
rewrite location 2
access location 1
access location 2



=== TEST 5: access + rewrite (http+location)
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "access http 1") }
    access_by_lua_block { ngx.log(ngx.ERR, "access http 2") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite http 1") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite http 2") }

    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access location 1") }
        access_by_lua_block { ngx.log(ngx.ERR, "access location 2") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite location 1") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite location 2") }
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/(rewrite|access) (http|location) \d/
--- grep_error_log_out
rewrite location 1
rewrite location 2
access location 1
access location 2



=== TEST 6: access + rewrite (server+http)
--- http_config
    access_by_lua_block { ngx.log(ngx.ERR, "access server 1") }
    access_by_lua_block { ngx.log(ngx.ERR, "access server 2") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite server 1") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite server 2") }
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "access http 1") }
    access_by_lua_block { ngx.log(ngx.ERR, "access http 2") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite http 1") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite http 2") }

    location /t {
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/(rewrite|access) (server|http) \d/
--- grep_error_log_out
rewrite http 1
rewrite http 2
access http 1
access http 2


=== TEST 6: access + rewrite (server+http+location)
--- http_config
    access_by_lua_block { ngx.log(ngx.ERR, "access server 1") }
    access_by_lua_block { ngx.log(ngx.ERR, "access server 2") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite server 1") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite server 2") }
--- config
    access_by_lua_block { ngx.log(ngx.ERR, "access http 1") }
    access_by_lua_block { ngx.log(ngx.ERR, "access http 2") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite http 1") }
    rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite http 2") }

    location /t {
        access_by_lua_block { ngx.log(ngx.ERR, "access location 1") }
        access_by_lua_block { ngx.log(ngx.ERR, "access location 2") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite location 1") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite location 2") }
        content_by_lua_block { ngx.say("Hello, Lua!") }
    }
--- request
GET /t
--- response_body
Hello, Lua!
--- grep_error_log eval
qr/(rewrite|access) (server|http|location) \d/
--- grep_error_log_out
rewrite location 1
rewrite location 2
access location 1
access location 2
