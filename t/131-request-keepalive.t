# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => repeat_each() * (2 * 4) + (2 * 3);

no_shuffle();
run_tests();

__DATA__

=== TEST 1: Get keepalive when on
--- config
        location /test {
            content_by_lua '
              ngx.say("Keepalive: ", tostring(ngx.req.get_keepalive()))
';
        }
--- pipelined_requests eval
["GET /test", "GET /test"]
--- response_body eval
["Keepalive: true\n", "Keepalive: false\n"]


=== TEST 2: Get keepalive when off
--- config
        location /test {
            content_by_lua '
              ngx.say("Keepalive: ", tostring(ngx.req.get_keepalive()))
';
        }
--- request eval
["GET /test", "GET /test"]
--- response_body eval
["Keepalive: false\n", "Keepalive: false\n"]

=== TEST 3: Set keepalive to off
--- config
        location /test {
            content_by_lua '
ngx.req.set_keepalive(false)
ngx.say("Keepalive disabled: " .. tostring(ngx.req.get_keepalive()))
';
        }
--- raw_request eval
["GET /test HTTP/1.1\r
Host: localhost\r
Connection: keep-alive\r
\r
"]
--- error_log eval
[qr/(?!closed keepalive connection)/]
--- response_body
Keepalive disabled: false



=== TEST 4: Set keepalive to on
--- config
        location /test {
            content_by_lua '
              ngx.req.set_keepalive(true)
              ngx.say("Keepalive: ", tostring(ngx.req.get_keepalive()))
';
        }
--- raw_request eval
["GET /test HTTP/1.1\r
Host: localhost\r
Connection: close\r
\r
"]
--- shutdown
--- error_log: closed keepalive connection
--- response_body eval
["Keepalive: true\n"]
