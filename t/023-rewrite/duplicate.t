# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#no_nginx_manager();
#log_level('warn');
#master_on();

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 8);

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
        content_by_lua_block { return }
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
        content_by_lua_block { return }
    }
--- request
GET /lua
--- response_body
Hello, Lua!



=== TEST 3: mix three styles
--- config
    location /lua {
        rewrite_by_lua ' ngx.log(ngx.ERR, "rewrite_by_lua") ';
        rewrite_by_lua_block { ngx.log(ngx.ERR, "rewrite_by_lua_block") }
        rewrite_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
ngx.log(ngx.ERR, "rewrite_by_lua_file")
ngx.print("Hello, Lua!\n")
--- request
GET /lua
--- response_body
Hello, Lua!
--- error_log
rewrite_by_lua
rewrite_by_lua_block
rewrite_by_lua_file



=== TEST 4: the first return status > 200
--- config
    location /lua {
        rewrite_by_lua_block { ngx.exit(503) }
        rewrite_by_lua_block { ngx.print("Hello, again Lua!\n") }
        content_by_lua_block { return }
    }
--- request
GET /lua
--- error_code: 503



=== TEST 5: the first return status == 0
--- config
    location /lua {
        rewrite_by_lua_block {
          ngx.log(ngx.ERR, "rewrite_by_lua_block first")
          ngx.exit(0)
        }
        rewrite_by_lua_block { ngx.print("Hello, Lua!\n") }
        content_by_lua_block { return }
    }
--- request
GET /lua
--- response_body
Hello, Lua!
--- error_log
rewrite_by_lua_block first



=== TEST 6: duplicate rewrite directives
--- config
    location /lua {
        rewrite_by_lua_block {
            ngx.log(ngx.ERR, "first rewrite before sleep")
            ngx.sleep(0.001)
            ngx.log(ngx.ERR, "first rewrite after sleep")
        }
        rewrite_by_lua_block { ngx.log(ngx.ERR, "second rewrite") }
        rewrite_by_lua_block { ngx.print("Hello, Lua!\n") }
        content_by_lua_block { ngx.print("Hello, again Lua!\n") }
    }
--- request
GET /lua
--- response_body
Hello, Lua!
--- error_log
first rewrite before sleep
first rewrite after sleep
second rewrite
