# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => blocks() * repeat_each() * 2;

$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();

no_long_string();
run_tests();

__DATA__

=== TEST 1: connection refused (unix domain socket)
--- config
    location /test {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("unix:/tmp/nosuchfile.sock")
            ngx.say("connect: ", ok, " ", err)

            local bytes
            bytes, err = sock:send("hello")
            ngx.say("send: ", bytes, " ", err)

            local line
            line, err = sock:receive()
            ngx.say("receive: ", line, " ", err)

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }
--- request
    GET /test
--- response_body
connect: nil no such file or directory
send: nil closed
receive: nil closed
close: nil closed

