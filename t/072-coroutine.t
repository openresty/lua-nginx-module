# vim:set ft=perl ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * blocks() * 2;

run_tests();

__DATA__

=== TEST 1: basic coroutine print
--- config
    location /lua {
        content_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

            function f()
                local cnt = 0
                while true do
                    ngx.say("Hello, ", cnt)
                    cy()
                    cnt = cnt + 1
                end
            end

            local c = cc(f)
            for i=1,3 do
                cr(c)
                ngx.say("***")
            end
        ';
    }
--- request
GET /lua
--- response_body
Hello, 0
***
Hello, 1
***
Hello, 2
***

