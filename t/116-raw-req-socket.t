# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * 36;

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

#log_level 'warn';
log_level 'debug';

#no_long_string();
#no_diff();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    server_tokens off;
    location = /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET /mysock HTTP/1.1\\r\\nUpgrade: mysock\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\nhello"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            local reader = sock:receiveuntil("\\r\\n\\r\\n")
            local data, err, partial = reader()
            if not data then
                ngx.say("no response header found")
                return
            end

            local msg, err = sock:receive()
            if not msg then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("msg: ", msg)

            ok, err = sock:close()
            if not ok then
                ngx.say("failed to close socket: ", err)
                return
            end
        ';
    }

    location = /mysock {
        content_by_lua '
            ngx.status = 101
            ngx.send_headers()
            ngx.flush(true)
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end

            local data, err = sock:receive(5)
            if not data then
                ngx.log(ngx.ERR, "server: failed to receive: ", err)
                return
            end

            local bytes, err = sock:send("1: received: " .. data .. "\\n")
            if not bytes then
                ngx.log(ngx.ERR, "server: failed to send: ", err)
                return
            end
        ';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
msg: 1: received: hello
--- error_log
lua raw req socket tcp_nodelay
--- no_error_log
[error]



=== TEST 2: header not sent yet
--- config
    server_tokens off;
    location = /t {
        content_by_lua '
            ngx.status = 101
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end
            local ok, err = sock:send("HTTP/1.1 200 OK\\r\\nContent-Length: 5\\r\\n\\r\\nhello")
            if not ok then
                ngx.log(ngx.ERR, "failed to send: ", err)
                return
            end
        ';
    }

--- raw_request eval
"GET /t HTTP/1.0\r
Host: localhost\r
Content-Length: 5\r
\r
hello"
--- response_headers
Content-Length: 5
--- response_body chop
hello
--- no_error_log
[error]



=== TEST 3: http 1.0 buffering
--- config
    server_tokens off;
    location = /t {
        content_by_lua '
            ngx.say("hello")
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return ngx.exit(500)
            end
        ';
    }

--- raw_request eval
"GET /t HTTP/1.0\r
Host: localhost\r
Upgrade: mysocket\r
\r
hello"
--- stap2
F(ngx_http_header_filter) {
    println("header filter")
}
F(ngx_http_lua_req_socket) {
    println("lua req socket")
}
--- ignore_response
--- error_log
server: failed to get raw req socket: http 1.0 buffering



=== TEST 4: multiple raw req sockets
--- config
    server_tokens off;
    location = /t {
        content_by_lua '
            ngx.say("hello")
            ngx.flush(true)
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end
            local sock2, err = ngx.req.socket(true)
            if not sock2 then
                ngx.log(ngx.ERR, "server: failed to get raw req socket2: ", err)
                return
            end

        ';
    }

--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost\r
Upgrade: mysocket\r
\r
hello"
--- stap2
F(ngx_http_header_filter) {
    println("header filter")
}
F(ngx_http_lua_req_socket) {
    println("lua req socket")
}
--- ignore_response
--- error_log
server: failed to get raw req socket2: duplicate call



=== TEST 5: ngx.say after ngx.req.socket(true)
--- config
    server_tokens off;
    location = /t {
        content_by_lua '
            ngx.send_headers()
            ngx.flush(true)
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end
            local ok, err = ngx.say("ok")
            if not ok then
                ngx.log(ngx.ERR, "failed to say: ", err)
                return
            end
        ';
    }

--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost\r
Upgrade: mysocket\r
\r
hello"
--- ignore_response
--- error_log
failed to say: raw request socket acquired



=== TEST 6: ngx.print after ngx.req.socket(true)
--- config
    server_tokens off;
    location = /t {
        content_by_lua '
            ngx.send_headers()
            ngx.flush(true)
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end
            local ok, err = ngx.print("ok")
            if not ok then
                ngx.log(ngx.ERR, "failed to print: ", err)
                return
            end
        ';
    }

--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost\r
Upgrade: mysocket\r
\r
hello"
--- ignore_response
--- error_log
failed to print: raw request socket acquired



=== TEST 7: ngx.eof after ngx.req.socket(true)
--- config
    server_tokens off;
    location = /t {
        content_by_lua '
            ngx.send_headers()
            ngx.flush(true)
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end
            local ok, err = ngx.eof()
            if not ok then
                ngx.log(ngx.ERR, "failed to eof: ", err)
                return
            end
        ';
    }

--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost\r
Upgrade: mysocket\r
\r
hello"
--- ignore_response
--- error_log
failed to eof: raw request socket acquired



=== TEST 8: ngx.flush after ngx.req.socket(true)
--- config
    server_tokens off;
    location = /t {
        content_by_lua '
            ngx.send_headers()
            ngx.flush(true)
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end
            local ok, err = ngx.flush()
            if not ok then
                ngx.log(ngx.ERR, "failed to flush: ", err)
                return
            end
        ';
    }

--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost\r
Upgrade: mysocket\r
\r
hello"
--- ignore_response
--- error_log
failed to flush: raw request socket acquired



=== TEST 9: receive timeout
--- config
    server_tokens off;
    postpone_output 1;
    location = /t {
        content_by_lua '
            ngx.send_headers()
            ngx.req.read_body()
            ngx.flush(true)
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end

            sock:settimeout(100)

            local data, err, partial = sock:receive(10)
            if not data then
                ngx.log(ngx.ERR, "server: 1: failed to receive: ", err, ", received: ", partial)
            end

            data, err, partial = sock:receive(10)
            if not data then
                ngx.log(ngx.ERR, "server: 2: failed to receive: ", err, ", received: ", partial)
            end

            ngx.exit(444)
        ';
    }

--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost\r
Upgrade: mysocket\r
Connection: close\r
\r
ab"
--- ignore_response
--- wait: 0.1
--- error_log
lua tcp socket read timed out
server: 1: failed to receive: timeout, received: ab,
server: 2: failed to receive: timeout, received: ,
--- no_error_log
[alert]



=== TEST 10: on_abort called during ngx.sleep()
--- config
    server_tokens off;
    lua_check_client_abort on;
    location = /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET /mysock HTTP/1.1\\r\\nUpgrade: mysock\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\nhello"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            local reader = sock:receiveuntil("\\r\\n\\r\\n")
            local data, err, partial = reader()
            if not data then
                ngx.say("no response header found")
                return
            end

            local msg, err = sock:receive()
            if not msg then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("msg: ", msg)

            ngx.sleep(0.1)

            ok, err = sock:close()
            if not ok then
                ngx.say("failed to close socket: ", err)
                return
            end
        ';
    }

    location = /mysock {
        content_by_lua '
            ngx.status = 101
            ngx.send_headers()
            ngx.flush(true)

            local ok, err = ngx.on_abort(function (premature) ngx.log(ngx.WARN, "mysock handler aborted") end)
            if not ok then
                ngx.log(ngx.ERR, "failed to set on_abort handler: ", err)
                return
            end

            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end

            local data, err = sock:receive(5)
            if not data then
                ngx.log(ngx.ERR, "server: failed to receive: ", err)
                return
            end

            local bytes, err = sock:send("1: received: " .. data .. "\\n")
            if not bytes then
                ngx.log(ngx.ERR, "server: failed to send: ", err)
                return
            end

            ngx.sleep(1)
        ';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
msg: 1: received: hello
--- error_log
mysock handler aborted
--- no_error_log
[error]
--- wait: 1.1



=== TEST 11: on_abort called during sock:receive()
--- config
    server_tokens off;
    lua_check_client_abort on;
    location = /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET /mysock HTTP/1.1\\r\\nUpgrade: mysock\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\nhello"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            local reader = sock:receiveuntil("\\r\\n\\r\\n")
            local data, err, partial = reader()
            if not data then
                ngx.say("no response header found")
                return
            end

            local msg, err = sock:receive()
            if not msg then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("msg: ", msg)

            ngx.sleep(0.1)

            ok, err = sock:close()
            if not ok then
                ngx.say("failed to close socket: ", err)
                return
            end
        ';
    }

    location = /mysock {
        content_by_lua '
            ngx.status = 101
            ngx.send_headers()
            ngx.flush(true)

            local ok, err = ngx.on_abort(function (premature) ngx.log(ngx.WARN, "mysock handler aborted") end)
            if not ok then
                ngx.log(ngx.ERR, "failed to set on_abort handler: ", err)
                return
            end

            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end

            local data, err = sock:receive(5)
            if not data then
                ngx.log(ngx.ERR, "server: failed to receive: ", err)
                return
            end

            local bytes, err = sock:send("1: received: " .. data .. "\\n")
            if not bytes then
                ngx.log(ngx.ERR, "server: failed to send: ", err)
                return
            end

            local data, err = sock:receive()
            if not data then
                ngx.log(ngx.WARN, "failed to receive a line: ", err)
                return
            end
        ';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
msg: 1: received: hello
--- error_log
failed to receive a line: client aborted
--- no_error_log
[error]
--- wait: 0.1



=== TEST 12: receiveuntil
--- config
    server_tokens off;
    location = /t {
        #set $port 5000;
        set $port $TEST_NGINX_SERVER_PORT;

        content_by_lua '
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET /mysock HTTP/1.1\\r\\nUpgrade: mysock\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\nhello"
            -- req = "OK"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            local bytes, err = sock:send(", ")
            if not bytes then
                ngx.say("failed to send packet 1: ", err)
                return
            end

            local bytes, err = sock:send("world")
            if not bytes then
                ngx.say("failed to send packet 2: ", err)
                return
            end

            local reader = sock:receiveuntil("\\r\\n\\r\\n")
            local data, err, partial = reader()
            if not data then
                ngx.say("no response header found")
                return
            end

            local msg, err = sock:receive()
            if not msg then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("msg: ", msg)

            ok, err = sock:close()
            if not ok then
                ngx.say("failed to close socket: ", err)
                return
            end
        ';
    }

    location = /mysock {
        content_by_lua '
            ngx.status = 101
            ngx.send_headers()
            ngx.flush(true)
            ngx.req.read_body()
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end

            local reader = sock:receiveuntil("rld")
            local data, err = reader()
            if not data then
                ngx.log(ngx.ERR, "server: failed to receive: ", err)
                return
            end

            local bytes, err = sock:send("1: received: " .. data .. "\\n")
            if not bytes then
                ngx.log(ngx.ERR, "server: failed to send: ", err)
                return
            end
        ';
        more_clear_headers Date;
    }

--- request
GET /t
--- response_body
msg: 1: received: hello, wo
--- no_error_log
[error]



=== TEST 13: request body not read yet
--- config
    server_tokens off;
    location = /t {
        content_by_lua '
            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.ERR, "server: failed to get raw req socket: ", err)
                return
            end

            local data, err = sock:receive(5)
            if not data then
                ngx.log(ngx.ERR, "failed to receive: ", err)
                return
            end

            local ok, err = sock:send("HTTP/1.1 200 OK\\r\\nContent-Length: 5\\r\\n\\r\\n" .. data)
            if not ok then
                ngx.log(ngx.ERR, "failed to send: ", err)
                return
            end
        ';
    }

--- raw_request eval
"GET /t HTTP/1.0\r
Host: localhost\r
Content-Length: 5\r
\r
hello"
--- response_headers
Content-Length: 5
--- response_body chop
hello
--- no_error_log
[error]



=== TEST 14: pending request body reading
--- config
    server_tokens off;
    location = /t {
        content_by_lua '
            ngx.thread.spawn(function ()
                ngx.req.read_body()
            end)

            local sock, err = ngx.req.socket(true)
            if not sock then
                ngx.log(ngx.WARN, "server: failed to get raw req socket: ", err)
                return ngx.exit(444)
            end

            local data, err = sock:receive(5)
            if not data then
                ngx.log(ngx.ERR, "failed to receive: ", err)
                return
            end

            local ok, err = sock:send("HTTP/1.1 200 OK\\r\\nContent-Length: 5\\r\\n\\r\\n" .. data)
            if not ok then
                ngx.log(ngx.ERR, "failed to send: ", err)
                return
            end
        ';
    }

--- raw_request eval
"GET /t HTTP/1.0\r
Host: localhost\r
Content-Length: 5\r
\r
hell"
--- ignore_response
--- no_error_log
[error]
[alert]
--- error_log
server: failed to get raw req socket: pending request body reading in some other thread

