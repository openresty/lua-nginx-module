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

