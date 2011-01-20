# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

#$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';

no_long_string();

run_tests();

__DATA__

=== TEST 1: code cache on by default
--- config
    location /lua {
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
32



=== TEST 2: code cache explicitly on
--- config
    location /lua {
        lua_code_cache on;
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
32



=== TEST 3: code cache explicitly off
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
101

