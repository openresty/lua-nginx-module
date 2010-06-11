# vi:ft=perl

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';
run_tests();

__DATA__

=== TEST 1: syntax error in lua code chunk
--- config
    location /lua {
        set_by_lua $res "return 1+";
        echo $res;
    }
--- request
GET /lua
--- error_code: 500
--- response_body_like: 500 Internal Server Error



=== TEST 2: syntax error in lua file
--- config
    location /lua {
        set_by_lua_file $res 'html/test.lua';
        echo $res;
    }
--- user_files
>>> test.lua
return 1+
--- request
GET /lua
--- error_code: 500
--- response_body_like: 500 Internal Server Error



=== TEST 3: syntax error in lua file (from Guang Feng)
--- config
    location /lua {
        set $res '[{"a":32},{"b":64}]';
        set_by_lua_file $list 'html/test.lua' $res;
        echo $list;
    }
--- user_files
>>> test.lua
-- local j = require('json')
local p = ngx.arg[1]
return p
--- request
GET /lua
--- response_body
[{"a":32},{"b":64}]

