# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_long_string();
#no_diff();
run_tests();

__DATA__

=== TEST 1: memcached read lines
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "flush_all\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local readline = sock:receiveuntil("\\r\\n")
            local line, err, part = readline()
            if line then
                ngx.say("received: ", line)

            else
                ngx.say("failed to receive a line: ", err, " [", part, "]")
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 11
received: OK
close: 1 nil
--- no_error_log
[error]



=== TEST 2: http read lines
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_CLIENT_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local readline = sock:receiveuntil("\\r\\n")
            local line, err, part

            for i = 1, 7 do
                line, err, part = readline()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: HTTP/1.1 200 OK
read: Server: nginx
read: Content-Type: text/plain
read: Content-Length: 4
read: Connection: close
read: 
failed to read a line: closed [foo
]
close: nil closed
}
--- no_error_log
[error]


=== TEST 2: http read all the headers in a single run
--- config
    server_tokens off;
    location /t {
        set $port $TEST_NGINX_CLIENT_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end
            ngx.say("request sent: ", bytes)

            local read_headers = sock:receiveuntil("\\r\\n\\r\\n")
            local line, err, part

            for i = 1, 2 do
                line, err, part = read_headers()
                if line then
                    ngx.say("read: ", line)

                else
                    ngx.say("failed to read a line: ", err, " [", part, "]")
                end
            end

            ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        ';
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body eval
qq{connected: 1
request sent: 57
read: HTTP/1.1 200 OK\r
Server: nginx\r
Content-Type: text/plain\r
Content-Length: 4\r
Connection: close
failed to read a line: closed [foo
]
close: nil closed
}
--- no_error_log
[error]

