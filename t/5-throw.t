# vi:ft=

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

#$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';

no_long_string();

run_tests();

__DATA__

=== TEST 1: throw 403
--- config
    location /lua {
        content_by_lua "ngx.throw_error(403);ngx.say('hi')";
    }
--- request
GET /lua
--- error_code: 403
--- response_body_like: 403 Forbidden



=== TEST 2: throw 404
--- config
    location /lua {
        content_by_lua "ngx.throw_error(404);ngx.say('hi');";
    }
--- request
GET /lua
--- error_code: 404
--- response_body_like: 404 Not Found



=== TEST 3: throw 404 after sending the header and partial body
--- config
    location /lua {
        content_by_lua "ngx.say('hi');ngx.throw_error(404);ngx.say(', you')";
    }
--- request
GET /lua
--- error_code: 200
--- response_body
hi



=== TEST 4: working with ngx_auth_request (succeeded)
--- config
    location /auth {
        content_by_lua "
            if ngx.var.user == 'agentzh' then
                ngx.eof();
            else
                ngx.throw_error(403)
            end";
    }
    location /api {
        set $user $arg_user;
        auth_request /auth;

        echo "Logged in";
    }
--- request
GET /api?user=agentzh
--- error_code: 200
--- response_body
Logged in



=== TEST 5: working with ngx_auth_request (failed)
--- config
    location /auth {
        content_by_lua "
            if ngx.var.user == 'agentzh' then
                ngx.eof();
            else
                ngx.throw_error(403)
            end";
    }
    location /api {
        set $user $arg_user;
        auth_request /auth;

        echo "Logged in";
    }
--- request
GET /api?user=agentz
--- error_code: 403
--- response_body_like: 403 Forbidden

