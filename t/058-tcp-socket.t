# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#repeat_each(2);

plan tests => blocks() * repeat_each() * 2;

#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.server_port
            -- local port = 1234
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = [[GET /foo HTTP/1.0\r
Host: localhost\r
Connection: close\r
\r
]]

            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
            end

            ngx.say("request sent: ", bytes)

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to receive the first line: ", err)
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
connected: 1
request sent: 53
received: HTTP/1.1 200 OK

