# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;
$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();

#log_level "warn";
#worker_connections(1024);
#master_on();

my $pwd = `pwd`;
chomp $pwd;
$ENV{TEST_NGINX_PWD} ||= $pwd;

our $LuaCpath = $ENV{LUA_CPATH} ||
    '/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;';

no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- http_config
    lua_package_path '$TEST_NGINX_PWD/t/lib/?.lua;;';
--- config
    location /test {
        content_by_lua '
            package.loaded["socket"] = ngx.socket
            local Redis = require "Redis"

            local redis = Redis.connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)

            redis:set("some_key", "hello 1234")
            local data = redis:get("some_key")
            ngx.say("some_key: ", data)
        ';
    }
--- request
    GET /test
--- response_body
some_key: hello 1234
--- no_error_log
[error]



=== TEST 2: coroutine-based pub/sub
--- http_config eval
qq{
    lua_package_path '\$TEST_NGINX_PWD/t/lib/?.lua;;';
    lua_package_cpath '$::LuaCpath';
}
--- config
    location /test {
        content_by_lua '
            package.loaded["socket"] = ngx.socket
            local Redis = require "Redis"

            local cjson = require "cjson"

            local r1 = Redis.connect("127.0.0.1", 6379)

            local r2 = Redis.connect("127.0.0.1", 6379)

            local loop = r2:pubsub({ subscribe = "foo" })
            local msg, abort = loop()
            ngx.say("msg type: ", type(msg))
            if msg then
                ngx.say("msg: ", cjson.encode(msg))
            end
            for i = 1, 3 do
                r1:publish("foo", "test " .. i)
                local msg, abort = loop()
                if msg then
                    ngx.say("msg: ", cjson.encode(msg))
                end
                ngx.say("abort: ", type(abort))
            end

            abort()

            msg, abort = loop()
            ngx.say("msg type: ", type(msg))
        ';
    }
--- request
    GET /test
--- response_body
msg type: table
msg: {"payload":1,"channel":"foo","kind":"subscribe"}
msg: {"payload":"test 1","channel":"foo","kind":"message"}
abort: function
msg: {"payload":"test 2","channel":"foo","kind":"message"}
abort: function
msg: {"payload":"test 3","channel":"foo","kind":"message"}
abort: function
msg type: nil
--- no_error_log
[error]

