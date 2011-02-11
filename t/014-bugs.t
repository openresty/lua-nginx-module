# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(120);
repeat_each(3);

plan tests => blocks() * repeat_each() * 2;

our $HtmlDir = html_dir;
#warn $html_dir;

#$ENV{LUA_PATH} = "$html_dir/?.lua";

#no_diff();
#no_long_string();

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    location /load {
        content_by_lua '
            package.loaded.foo = nil;
            local foo = require "foo";
            foo.hi()
        ';
    }
--- request
GET /load
--- user_files
>>> foo.lua
module(..., package.seeall);

function foo () 
    return 1
    return 2
end
--- error_code: 500
--- response_body_like: 500 Internal Server Error



=== TEST 2: sanity
--- http_config
lua_package_path '/home/agentz/rpm/BUILD/lua-yajl-1.1/build/?.so;/home/lz/luax/?.so;./?.so';
--- config
    location = '/report/listBidwordPrices4lzExtra.htm' {
        content_by_lua '
            local yajl = require "yajl"
            local w = ngx.var.arg_words
            w = ngx.unescape_uri(w)
            local r = {}
            print("start for")
            for id in string.gmatch(w, "%d+") do
                 r[id] = -1
            end
            print("end for, start yajl")
            ngx.print(yajl.to_string(r))
            print("end yajl")
        ';
    }
--- request
GET /report/listBidwordPrices4lzExtra.htm?words=123,156,2532
--- response_body
--- SKIP



=== TEST 3: sanity
I dunno why this test is not passing. TODO'ing...
--- config
    location = /memc {
        #set $memc_value 'hello';
        set $memc_value $arg_v;
        set $memc_cmd $arg_c;
        set $memc_key $arg_k;
        #set $memc_value hello;

        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
        #echo $memc_value;
    }
    location = /echo {
        echo_location '/memc?c=get&k=foo';
        echo_location '/memc?c=set&k=foo&v=hello';
        echo_location '/memc?c=get&k=foo';
    }
    location = /main {
        content_by_lua '
            res = ngx.location.capture("/memc?c=get&k=foo&v=")
            ngx.say("1: ", res.body)

            res = ngx.location.capture("/memc?c=set&k=foo&v=bar");
            ngx.say("2: ", res.body);

            res = ngx.location.capture("/memc?c=get&k=foo")
            ngx.say("3: ", res.body);
        ';
    }
--- request
GET /main
--- response_body_like: 3: bar$
--- SKIP



=== TEST 4: capture works for subrequests with internal redirects
--- config
    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/")
            ngx.say(res.status)
            ngx.print(res.body)
        ';
    }
--- request
    GET /lua
--- response_body_like chop
200
.*It works
--- SKIP



=== TEST 5: disk file bufs not working
--- config
    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/test.lua")
            ngx.say(res.status)
            ngx.print(res.body)
        ';
    }
--- user_files
>>> test.lua
print("Hello, world")
--- request
    GET /lua
--- response_body
200
print("Hello, world")



=== TEST 6: print lua empty strings
--- config
    location /lua {
        content_by_lua 'ngx.print("") ngx.flush() ngx.print("Hi")';
    }
--- request
GET /lua
--- response_body chop
Hi



=== TEST 7: say lua empty strings
--- config
    location /lua {
        content_by_lua 'ngx.say("") ngx.flush() ngx.print("Hi")';
    }
--- request
GET /lua
--- response_body eval
"
Hi"

