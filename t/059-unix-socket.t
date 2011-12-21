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
            ngx.say(ok, " ", err)
        ';
    }
--- request
    GET /test
--- response_body
nil no such file or directory

