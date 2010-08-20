# vi:ft=

use lib 'lib';
use Test::Nginx::Socket;

#repeat_each(20000);
repeat_each(2);
master_on();
workers(1);
#log_level('debug');
log_level('warn');
worker_connections(1000);

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
--- error_code:
--- response_body:



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



=== TEST 6: working with ngx_auth_request (failed)
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:3306 dbname=test
             password=some_pass user=monty protocol=mysql;
        drizzle_keepalive max=300 mode=single overflow=ignore;
    }

    upstream memc_a {
        server 127.0.0.1:11984;
        keepalive 300 single;
    }

    upstream memc_b {
        server 127.0.0.1:11211;
        keepalive 300 single;
    }

    upstream_list memc_cluster memc_a memc_b;

    lua_package_cpath '/home/lz/luax/?.so';
--- config
    location /memc {
        internal;

        set $memc_key $arg_key;
        set $memc_exptime $arg_exptime;

        set_hashed_upstream $backend memc_cluster $arg_key;
        memc_pass $backend;
    }

    location /conv-uid-mysql {
        internal;

        set $key "conv-uid-$arg_uid";

        srcache_fetch GET /memc key=$key;
        srcache_store PUT /memc key=$key;

        default_type 'application/json';

        drizzle_query "select new_uid as uid from conv_uid where old_uid=$arg_uid";
        drizzle_pass backend;

        rds_json on;
    }

    location /conv-uid {
        internal;
        content_by_lua_file 'html/foo.lua';
    }
    location /api {
        set $uid $arg_uid;
        auth_request /conv-uid;

        echo "Logged in $uid";
    }
--- user_files
>>> foo.lua
local yajl = require('yajl');
local old_uid = ngx.var.uid
-- print('about to run sr')
local res = ngx.location.capture('/conv-uid-mysql?uid=' .. old_uid)
-- print('just have run sr' .. res.body)
if (res.status ~= ngx.HTTP_OK) then
    ngx.throw_error(res.status)
end
res = yajl.to_value(res.body)
if (not res or not res[1] or not res[1].uid or
        not string.match(res[1].uid, '^%d+$')) then
    ngx.throw_error(ngx.HTTP_INTERNAL_SERVER_ERROR)
end
ngx.var.uid = res[1].uid;
-- print('done')
--- request
GET /api?uid=32
--- response_body
Logged in 56
--- SKIP

