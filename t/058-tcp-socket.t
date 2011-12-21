# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#repeat_each(2);

plan tests => blocks() * repeat_each() * 2;

$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();

no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
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
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err)
                    break
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
--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
failed to receive a line: closed
close: nil closed



=== TEST 2: no trailing newline
--- config
    server_tokens off;
    location /t {
        #set $port 1234;
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
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            while true do
                local line, err = sock:receive()
                if line then
                    ngx.say("received: ", line)

                else
                    ngx.say("failed to receive a line: ", err)
                    break
                end
            end

            sock:close()
            ngx.say("closed")
        ';
    }

    location /foo {
        echo -n foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 57
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 3
received: Connection: close
received: 
failed to receive a line: closed
closed



=== TEST 3: no resolver defined
--- config
    server_tokens off;
    location /t {
        #set $port 1234;
        set $port $TEST_NGINX_CLIENT_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("agentzh.org", port)
            if not ok then
                ngx.say("failed to connect: ", err)
            end

            ngx.say("connected: ", ok)

            local req = "GET /foo HTTP/1.0\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)
        ';
    }
--- request
GET /t
--- response_body
failed to connect: no resolver defined to resolve "agentzh.org"
connected: nil
failed to send request: closed



=== TEST 4: with resolver
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = 80
            local ok, err = sock:connect("agentzh.org", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET / HTTP/1.0\\r\\nHost: agentzh.org\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)

            local line, err = sock:receive()
            if line then
                ngx.say("first line received: ", line)

            else
                ngx.say("failed to receive the first line: ", err)
            end

            line, err = sock:receive()
            if line then
                ngx.say("second line received: ", line)

            else
                ngx.say("failed to receive the second line: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body
connected: 1
request sent: 56
first line received: HTTP/1.1 200 OK
second line received: Server: ngx_openresty



=== TEST 5: connection refused (tcp)
--- config
    location /test {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", 16787)
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
connect: nil connection refused
send: nil closed
receive: nil closed
close: nil closed



=== TEST 6: connection timeout (tcp)
--- config
    resolver $TEST_NGINX_RESOLVER;
    lua_socket_connect_timeout 100ms;
    lua_socket_send_timeout 100ms;
    lua_socket_read_timeout 100ms;
    location /test {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("taobao.com", 16787)
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
connect: nil timeout
send: nil closed
receive: nil closed
close: nil closed



=== TEST 7: not closed manually
--- config
    server_tokens off;
    location /t {
        #set $port 5000;
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
        ';
    }

    location /foo {
        echo foo;
        more_clear_headers Date;
    }
--- request
GET /t
--- response_body
connected: 1



=== TEST 8: resolver error (host not found)
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = 80
            local ok, err = sock:connect("blah-blah-not-found.agentzh.org", port)
            print("connected: ", ok, " ", err, " ", not ok)
            if not ok then
                ngx.say("failed to connect: ", err)
            end

            ngx.say("connected: ", ok)

            local req = "GET / HTTP/1.0\\r\\nHost: agentzh.org\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)
        ';
    }
--- request
GET /t
--- timeout: 5
--- response_body
failed to connect: blah-blah-not-found.agentzh.org could not be resolved (3: Host not found)
connected: nil
failed to send request: closed



=== TEST 9: resolver error (timeout)
--- config
    server_tokens off;
    resolver 121.14.24.241;
    resolver_timeout 100ms;
    location /t {
        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = 80
            local ok, err = sock:connect("blah-blah-not-found.agentzh.org", port)
            print("connected: ", ok, " ", err, " ", not ok)
            if not ok then
                ngx.say("failed to connect: ", err)
            end

            ngx.say("connected: ", ok)

            local req = "GET / HTTP/1.0\\r\\nHost: agentzh.org\\r\\nConnection: close\\r\\n\\r\\n"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent: ", bytes)
        ';
    }
--- request
GET /t
--- timeout: 5
--- response_body
failed to connect: blah-blah-not-found.agentzh.org could not be resolved (110: Operation timed out)
connected: nil
failed to send request: closed

