# vi:ft=
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(120);
repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

my $html_dir = html_dir;
#warn $html_dir;

$ENV{LUA_PATH} = "$html_dir/?.lua";

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /main {
        echo_location /load;
        echo_location /check;
        echo_location /check;
    }

    location /load {
        content_by_lua '
            package.loaded.foo = null;
            local foo = require "foo";
            foo.hi()';
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

