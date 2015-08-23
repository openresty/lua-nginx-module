# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

run_tests();

__DATA__

=== TEST 1: running count with no running timers
--- config
    location /timers {
        content_by_lua 'ngx.say(ngx.timer.running_count())';
    }
--- request
GET /timers
--- response_body
0



=== TEST 2: running count with no pending timers
--- config
    location /timers {
        content_by_lua 'ngx.say(ngx.timer.pending_count())';
    }
--- request
GET /timers
--- response_body
0



=== TEST 3: pending count with pending timer
--- config
    location /timers {
        content_by_lua '
            ngx.timer.at(0.05, function() end)
            ngx.say(ngx.timer.pending_count())
        ';
    }
--- request
GET /timers
--- response_body
1
