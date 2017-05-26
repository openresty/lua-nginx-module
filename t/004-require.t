# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#log_level('warn');

#master_on();
#repeat_each(120);
repeat_each(2);

plan tests => blocks() * repeat_each() * 2;

our $HtmlDir = html_dir;
#warn $html_dir;

#$ENV{LUA_PATH} = "$html_dir/?.lua";

#no_diff();
no_long_string();
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
                foo.hi()
            else
                ngx.say("not found")
            end
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



=== TEST 7: require "ngx" (content_by_lua)
--- config
    location /ngx {
        content_by_lua '
            local ngx = require "ngx"
            ngx.say("hello, world")
        ';
    }
--- request
GET /ngx
--- response_body
hello, world



=== TEST 8: require "ngx" (set_by_lua)
--- config
    location /ngx {
        set_by_lua $res '
            local ngx = require "ngx"
            return ngx.escape_uri(" ")
        ';
        echo $res;
    }
--- request
GET /ngx
--- response_body
%20



=== TEST 9: require "ndk" (content_by_lua)
--- config
    location /ndk {
        content_by_lua '
            local ndk = require "ndk"
            local res = ndk.set_var.set_escape_uri(" ")
            ngx.say(res)
        ';
    }
--- request
GET /ndk
--- response_body
%20



=== TEST 10: require "ndk" (set_by_lua)
--- config
    location /ndk {
        set_by_lua $res '
            local ndk = require "ndk"
            return ndk.set_var.set_escape_uri(" ")
        ';
        echo $res;
    }
--- request
GET /ndk
--- response_body
%20



=== TEST 11: append package path
--- http_config
    append_lua_package_path "/opt/program/?.lua;";
--- config
    location /main {
        content_by_lua '
            local m = ngx.re.match(package.path, [[/opt/program/\?\.lua]])
            if m then
                ngx.say([[the "program" package path found]])
            end
        ';
    }
--- request
GET /main
--- response_body
the "program" package path found



=== TEST 12: append package path (multi)
--- http_config
    append_lua_package_path "/opt/program/?.lua;";
    append_lua_package_path "/opt/program2/?.lua;";
--- config
    location /main {
        content_by_lua '
            local m = ngx.re.match(package.path, [[/opt/program/\?\.lua]])
            if m then
                ngx.say([[the "program" package path found]])
            end

            local m = ngx.re.match(package.path, [[/opt/program2/\?\.lua]])
            if m then
                ngx.say([[the "program2" package path found]])
            end
        ';
    }
--- request
GET /main
--- response_body
the "program" package path found
the "program2" package path found



=== TEST 13: append package cpath
--- http_config
    append_lua_package_cpath "/opt/program/?.so;";
--- config
    location /main {
        content_by_lua '
            local m = ngx.re.match(package.cpath, [[/opt/program/\?\.so]])
            if m then
                ngx.say([[the "program" package cpath found]])
            end
        ';
    }
--- request
GET /main
--- response_body
the "program" package cpath found



=== TEST 14: append package cpath (multi)
--- http_config
    append_lua_package_cpath "/opt/program/?.so;";
    append_lua_package_cpath "/opt/program2/?.so;";
--- config
    location /main {
        content_by_lua '
            local m = ngx.re.match(package.cpath, [[/opt/program/\?\.so]])
            if m then
                ngx.say([[the "program" package cpath found]])
            end

            local m = ngx.re.match(package.cpath, [[/opt/program2/\?\.so]])
            if m then
                ngx.say([[the "program2" package cpath found]])
            end
        ';
    }
--- request
GET /main
--- response_body
the "program" package cpath found
the "program2" package cpath found



=== TEST 15: append package path (with lua_package_path)
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;;';
    append_lua_package_path '/opt/program/?.lua;';"
--- config
    location /main {
        content_by_lua '
            ngx.print(package.path)
        ';
    }
--- request
GET /main
--- response_body_like: /opt/program/\?.lua;[^;]+/servroot/html/\?.lua;.+lua;$



=== TEST 16: append package cpath (with lua_package_cpath)
--- http_config eval
    "lua_package_cpath '$::HtmlDir/?.so;;';
    append_lua_package_cpath '/opt/program/?.so;';"
--- config
    location /main {
        content_by_lua '
            ngx.print(package.cpath)
        ';
    }
--- request
GET /main
--- response_body_like: /opt/program/\?.so;[^;]+/servroot/html/\?.so;.+so;$
