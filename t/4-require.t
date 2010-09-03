# vim:set ft=perl ts=4 sw=4 et fdm=marker:
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
    location /main {
        echo_location /load;
        echo_location /check;
        echo_location /check;
    }

    location /load {
        content_by_lua '
            package.loaded.foo = nil;
            local foo = require "foo";
            foo.hi()
        ';
    }

    location /check {
        content_by_lua '
            local foo = package.loaded.foo
            if foo then
                ngx.say("found")
            else
                ngx.say("not found")
            end
            foo.hi()
        ';
    }
--- request
GET /main
--- user_files
>>> foo.lua
module(..., package.seeall);

ngx.say("loading");

function hi ()
    ngx.say("hello, foo")
end;
--- response_body
loading
hello, foo
found
hello, foo
found
hello, foo



=== TEST 2: sanity
--- http_config eval
    "lua_package_cpath '$::HtmlDir/?.so';"
--- config
    location /main {
        content_by_lua '
            ngx.print(package.cpath);
        ';
    }
--- request
GET /main
--- user_files
--- response_body_like: ^[^;]+/servroot/html/\?.so$



=== TEST 3: expand default path (after)
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;;';"
--- config
    location /main {
        content_by_lua '
            ngx.print(package.path);
        ';
    }
--- request
GET /main
--- response_body_like: ^[^;]+/servroot/html/\?.lua;.+\.lua;$



=== TEST 4: expand default cpath (after)
--- http_config eval
    "lua_package_cpath '$::HtmlDir/?.so;;';"
--- config
    location /main {
        content_by_lua '
            ngx.print(package.cpath);
        ';
    }
--- request
GET /main
--- response_body_like: ^[^;]+/servroot/html/\?.so;.+\.so;$



=== TEST 5: expand default path (before)
--- http_config eval
    "lua_package_path ';;$::HtmlDir/?.lua';"
--- config
    location /main {
        content_by_lua '
            ngx.print(package.path);
        ';
    }
--- request
GET /main
--- response_body_like: ^.+\.lua;[^;]+/servroot/html/\?.lua$



=== TEST 6: expand default cpath (before)
--- http_config eval
    "lua_package_cpath ';;$::HtmlDir/?.so';"
--- config
    location /main {
        content_by_lua '
            ngx.print(package.cpath);
        ';
    }
--- request
GET /main
--- response_body_like: ^.+\.so;[^;]+/servroot/html/\?.so$

