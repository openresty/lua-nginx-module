# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#no_nginx_manager();
#log_level('warn');
#master_on();

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: duplicate rewrite directives
--- config
    location /lua {
        rewrite_by_lua_block { ngx.log(ngx.ERR, "first rewrite") }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "second rewrite") }
        rewrite_by_lua_block { ngx.print("Hello, Lua!\n") }
        content_by_lua return;
    }
--- request
GET /lua
--- response_body
Hello, Lua!
--- error_log
first rewrite
second rewrite



=== TEST 2: the first return status == 200
--- config
    location /lua {
        rewrite_by_lua_block { ngx.print("Hello, Lua!\n") }
        rewrite_by_lua_block { ngx.print("Hello, again Lua!\n") }
        content_by_lua return;
    }
--- request
GET /lua
--- response_body
Hello, Lua!
