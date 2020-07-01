# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => blocks() * repeat_each() * 2;

run_tests();

__DATA__

=== TEST 1: ngx.say (integer)
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(2)
        }
    }
--- request
GET /lua
--- response_body
2



=== TEST 2: ngx.say (floating point number)
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(3.1415926)
        }
    }
--- request
GET /lua
--- response_body
3.1415926



=== TEST 3: ngx.say (table with number)
--- config
    location /lua {
        content_by_lua_block {
            local data = {123," ", 3.1415926}
            ngx.say(data)
        }
    }
--- request
GET /lua
--- response_body
123 3.1415926
