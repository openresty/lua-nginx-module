# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();
#$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

no_long_string();
#no_diff();
#log_level 'warn';

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua '
            local sock, err = ngx.req.socket()
            if sock then
                ngx.say("got the request socket")
            else
                ngx.say("failed to get the request socket: ", err)
            end

            for i = 1, 3 do
                local data, err, part = sock:receive(5)
                if data then
                    ngx.say("received: ", data)
                else
                    ngx.say("failed to receive: ", err, " [", part, "]")
                end
            end
        ';
    }
--- request
POST /t
hello world
--- response_body
got the request socket
received: hello
received:  worl
failed to receive: closed [d]
--- no_error_log
[error]

