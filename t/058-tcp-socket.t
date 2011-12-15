# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => blocks() * repeat_each() * 2;

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp
            local ok, err = sock:connect("127.0.0.1", ngx.var.server_port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected.")

            local ok, err = sock:send("GET /foo HTTP/1.0")
            if not ok then
                ngx.say("failed to send request: ", err)
            end

            ngx.say("request sent")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to receive the first line")
            end

            ngx.say("received: ", line)

            sock:close()
        ';
    }

    location /foo {
        echo foo;
    }
--- request
GET /t
--- response_body
connected.
request sent.
received: 200 OK HTTP/1.1

