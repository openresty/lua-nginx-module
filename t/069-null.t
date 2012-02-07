# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

#master_on();
#workers(1);
#log_level('debug');
#log_level('warn');
#worker_connections(1024);

plan tests => blocks() * repeat_each() * 2;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;

$ENV{LUA_CPATH} ||= '/usr/local/openresty/lualib/?.so;;';

no_long_string();

run_tests();

__DATA__

=== TEST 1: compare ngx.null with cjson.null
--- config
    location /lua {
        content_by_lua '
            local cjson = require "cjson"
            ngx.say(cjson.null == ngx.null)
            ngx.say(cjson.encode(ngx.null))
        ';
    }
--- request
GET /lua
--- response_body
true
null



=== TEST 2: output ngx.null
--- config
    location /lua {
        content_by_lua '
            ngx.say("ngx.null: ", ngx.null)
        ';
    }
--- request
GET /lua
--- response_body
ngx.null: null



=== TEST 3: output ngx.null in a table
--- config
    location /lua {
        content_by_lua '
            ngx.say({"ngx.null: ", ngx.null})
        ';
    }
--- request
GET /lua
--- response_body
ngx.null: null

