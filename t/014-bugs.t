# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(120);
repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

our $HtmlDir = html_dir;
#warn $html_dir;

#$ENV{LUA_PATH} = "$html_dir/?.lua";

#no_diff();
#no_long_string();

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

