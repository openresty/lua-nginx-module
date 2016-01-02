# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(3);

plan tests => repeat_each() * (blocks() * 6 + 22);

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: simple logging
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua 'print("ssl cert by lua is running!")';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
ssl_certificate_by_lua:1: ssl cert by lua is running!

--- no_error_log
[error]
[alert]



=== TEST 2: sleep
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local begin = ngx.now()
            ngx.sleep(0.1)
            print("elapsed in ssl cert by lua: ", ngx.now() - begin)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log eval
[
'lua ssl server name: "test.com"',
qr/elapsed in ssl cert by lua: 0.(?:09|1[01])\d+,/,
]

--- no_error_log
[error]
[alert]



=== TEST 3: timer
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local function f()
                print("my timer run!")
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to create timer: ", err)
                return
            end
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
my timer run!

--- no_error_log
[error]
[alert]



=== TEST 4: cosocket
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect to memc: ", err)
                return
            end

            local bytes, err = sock:send("flush_all\\r\\n")
            if not bytes then
                ngx.log(ngx.ERR, "failed to send flush_all command: ", err)
                return
            end

            local res, err = sock:receive()
            if not res then
                ngx.log(ngx.ERR, "failed to receive memc reply: ", err)
                return
            end

            print("received memc reply: ", res)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
received memc reply: OK

--- no_error_log
[error]
[alert]



=== TEST 5: clear certs
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"
            ssl.clear_certs()
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log
lua ssl server name: "test.com"
sslv3 alert handshake failure

--- no_error_log
[alert]
[emerg]



=== TEST 6: set DER cert and private key
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            ssl.clear_certs()

            local f = assert(io.open("t/cert/test.crt.der"))
            local cert_data = f:read("*a")
            f:close()

            local ok, err = ssl.set_der_cert(cert_data)
            if not ok then
                ngx.log(ngx.ERR, "failed to set DER cert: ", err)
                return
            end

            local f = assert(io.open("t/cert/test.key.der"))
            local pkey_data = f:read("*a")
            f:close()

            local ok, err = ssl.set_der_priv_key(pkey_data)
            if not ok then
                ngx.log(ngx.ERR, "failed to set DER cert: ", err)
                return
            end
        ';
        ssl_certificate ../../cert/test2.crt;
        ssl_certificate_key ../../cert/test2.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 7: read SNI name via ssl.server_name()
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"
            print("read SNI name from Lua: ", ssl.server_name())
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
read SNI name from Lua: test.com

--- no_error_log
[error]
[alert]



=== TEST 8: read SNI name via ssl.server_name() when no SNI name specified
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"
            local name = ssl.server_name(),
            print("read SNI name from Lua: ", name, ", type: ", type(name))
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, nil, true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
read SNI name from Lua: nil, type: nil

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 9: read raw server addr via ssl.raw_server_addr() (unix domain socket)
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"
            local addr, addrtyp, err = ssl.raw_server_addr()
            if not addr then
                ngx.log(ngx.ERR, "failed to fetch raw server addr: ", err)
                return
            end
            if addrtyp == "inet" then  -- IPv4
                ip = string.format("%d.%d.%d.%d", byte(addr, 1), byte(addr, 2),
                                   byte(addr, 3), byte(addr, 4))
                print("Using IPv4 address: ", ip)

            elseif addrtyp == "inet6" then  -- IPv6
                ip = string.format("%d.%d.%d.%d", byte(addr, 13), byte(addr, 14),
                                   byte(addr, 15), byte(addr, 16))
                print("Using IPv6 address: ", ip)

            else  -- unix
                print("Using unix socket file ", addr)
            end
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log eval
[
'lua ssl server name: "test.com"',
qr/Using unix socket file .*?nginx\.sock/
]

--- no_error_log
[error]
[alert]



=== TEST 10: read raw server addr via ssl.raw_server_addr() (IPv4)
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.1:12345 ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"
            local byte = string.byte

            local addr, addrtyp, err = ssl.raw_server_addr()
            if not addr then
                ngx.log(ngx.ERR, "failed to fetch raw server addr: ", err)
                return
            end
            if addrtyp == "inet" then  -- IPv4
                ip = string.format("%d.%d.%d.%d", byte(addr, 1), byte(addr, 2),
                                   byte(addr, 3), byte(addr, 4))
                print("Using IPv4 address: ", ip)

            elseif addrtyp == "inet6" then  -- IPv6
                ip = string.format("%d.%d.%d.%d", byte(addr, 13), byte(addr, 14),
                                   byte(addr, 15), byte(addr, 16))
                print("Using IPv6 address: ", ip)

            else  -- unix
                print("Using unix socket file ", addr)
            end
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.1", 12345)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
Using IPv4 address: 127.0.0.1

--- no_error_log
[error]
[alert]



=== TEST 11: read raw server addr via ssl.raw_server_addr() (IPv6)
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen [::1]:12345 ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"
            local byte = string.byte

            local addr, addrtyp, err = ssl.raw_server_addr()
            if not addr then
                ngx.log(ngx.ERR, "failed to fetch raw server addr: ", err)
                return
            end
            if addrtyp == "inet" then  -- IPv4
                ip = string.format("%d.%d.%d.%d", byte(addr, 1), byte(addr, 2),
                                   byte(addr, 3), byte(addr, 4))
                print("Using IPv4 address: ", ip)

            elseif addrtyp == "inet6" then  -- IPv6
                ip = string.format("%d.%d.%d.%d", byte(addr, 13), byte(addr, 14),
                                   byte(addr, 15), byte(addr, 16))
                print("Using IPv6 address: ", ip)

            else  -- unix
                print("Using unix socket file ", addr)
            end
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("[::1]", 12345)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
Using IPv6 address: 0.0.0.1

--- no_error_log
[error]
[alert]



=== TEST 12: set DER cert chain
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            ssl.clear_certs()

            local f = assert(io.open("t/cert/chain/chain.der"))
            local cert_data = f:read("*a")
            f:close()

            local ok, err = ssl.set_der_cert(cert_data)
            if not ok then
                ngx.log(ngx.ERR, "failed to set DER cert: ", err)
                return
            end

            local f = assert(io.open("t/cert/chain/test-com.key.der"))
            local pkey_data = f:read("*a")
            f:close()

            local ok, err = ssl.set_der_priv_key(pkey_data)
            if not ok then
                ngx.log(ngx.ERR, "failed to set DER cert: ", err)
                return
            end
        ';
        ssl_certificate ../../cert/test2.crt;
        ssl_certificate_key ../../cert/test2.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/chain/root-ca.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 13: read PEM cert chain but set DER cert chain
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            ssl.clear_certs()

            local f = assert(io.open("t/cert/chain/chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local ok, err = ssl.set_der_cert(cert_data)
            if not ok then
                ngx.log(ngx.ERR, "failed to set DER cert: ", err)
                return
            end

            local f = assert(io.open("t/cert/chain/test-com.key.der"))
            local pkey_data = f:read("*a")
            f:close()

            local ok, err = ssl.set_der_priv_key(pkey_data)
            if not ok then
                ngx.log(ngx.ERR, "failed to set DER cert: ", err)
                return
            end
        ';
        ssl_certificate ../../cert/test2.crt;
        ssl_certificate_key ../../cert/test2.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/chain/root-ca.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 14: get OCSP responder (good case)
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local url, err = ssl.get_ocsp_responder_from_der_chain(cert_data)
            if not url then
                ngx.log(ngx.ERR, "failed to get OCSP responder: ", err)
                return
            end

            ngx.log(ngx.WARN, "OCSP url found: ", url)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
OCSP url found: http://127.0.0.1:8888/ocsp?foo=1,

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 15: get OCSP responder (not found)
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/chain/chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local url, err = ssl.get_ocsp_responder_from_der_chain(cert_data)
            if not url then
                if err then
                    ngx.log(ngx.ERR, "failed to get OCSP responder: ", err)
                else
                    ngx.log(ngx.WARN, "OCSP responder not found")
                end
                return
            end

            ngx.log(ngx.WARN, "OCSP url found: ", url)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
OCSP responder not found

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 16: get OCSP responder (no issuer cert at all)
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/test-com.crt"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local url, err = ssl.get_ocsp_responder_from_der_chain(cert_data)
            if not url then
                if err then
                    ngx.log(ngx.ERR, "failed to get OCSP responder: ", err)
                else
                    ngx.log(ngx.WARN, "OCSP responder not found")
                end
                return
            end

            ngx.log(ngx.WARN, "OCSP url found: ", url)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
failed to get OCSP responder: no issuer certificate in chain

--- no_error_log
[alert]
[emerg]



=== TEST 17: get OCSP responder (issuer cert not next to the leaf cert)
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/wrong-issuer-order-chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local url, err = ssl.get_ocsp_responder_from_der_chain(cert_data)
            if not url then
                if err then
                    ngx.log(ngx.ERR, "failed to get OCSP responder: ", err)
                else
                    ngx.log(ngx.WARN, "OCSP responder not found")
                end
                return
            end

            ngx.log(ngx.WARN, "OCSP url found: ", url)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
failed to get OCSP responder: issuer certificate not next to leaf

--- no_error_log
[alert]
[emerg]



=== TEST 18: get OCSP responder (truncated)
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local url, err = ssl.get_ocsp_responder_from_der_chain(cert_data,
                                    6)
            if not url then
                if err then
                    ngx.log(ngx.ERR, "failed to get OCSP responder: ", err)
                else
                    ngx.log(ngx.WARN, "OCSP responder not found")
                end
                return
            end

            if err then
                ngx.log(ngx.WARN, "still get an error: ", err)
            end

            ngx.log(ngx.WARN, "OCSP url found: ", url)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
OCSP url found: http:/,
still get an error: truncated

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 19: create OCSP request (good)
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local req, err = ssl.create_ocsp_request(cert_data)
            if not req then
                ngx.log(ngx.ERR, "failed to create OCSP request: ", err)
                return
            end

            ngx.log(ngx.WARN, "OCSP request created with length ", #req)

            local f = assert(io.open("t/cert/ocsp/ocsp-req.der", "r"))
            local expected = assert(f:read("*a"))
            f:close()
            if req ~= expected then
                ngx.log(ngx.ERR, "ocsp responder: got unexpected OCSP request")
            end
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
OCSP request created with length 68

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 20: create OCSP request (buffer too small)
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local req, err = ssl.create_ocsp_request(cert_data, 67)
            if not req then
                ngx.log(ngx.ERR, "failed to create OCSP request: ", err)
                return
            end

            ngx.log(ngx.WARN, "OCSP request created with length ", #req)
            local bytes = {string.byte(req, 1, #req)}
            for i, byte in ipairs(bytes) do
                bytes[i] = string.format("%02x", byte)
            end
            ngx.log(ngx.WARN, "OCSP request content: ", table.concat(bytes, " "))
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
failed to create OCSP request: output buffer too small: 68 > 67

--- no_error_log
[alert]
[emerg]



=== TEST 21: create OCSP request (empty string cert chain)
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local cert_data = ""
            local req, err = ssl.create_ocsp_request(cert_data, 67)
            if not req then
                ngx.log(ngx.ERR, "failed to create OCSP request: ", err)
                return ngx.exit(ngx.ERROR)
            end

            ngx.log(ngx.WARN, "OCSP request created with length ", #req)
            local bytes = {string.byte(req, 1, #req)}
            for i, byte in ipairs(bytes) do
                bytes[i] = string.format("%02x", byte)
            end
            ngx.log(ngx.WARN, "OCSP request content: ", table.concat(bytes, " "))
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log
lua ssl server name: "test.com"
failed to create OCSP request: d2i_X509_bio() failed

--- no_error_log
[alert]
[emerg]



=== TEST 22: create OCSP request (no issuer cert in the chain)
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/test-com.crt"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local req, err = ssl.create_ocsp_request(cert_data, 67)
            if not req then
                ngx.log(ngx.ERR, "failed to create OCSP request: ", err)
                return
            end

            ngx.log(ngx.WARN, "OCSP request created with length ", #req)
            local bytes = {string.byte(req, 1, #req)}
            for i, byte in ipairs(bytes) do
                bytes[i] = string.format("%02x", byte)
            end
            ngx.log(ngx.WARN, "OCSP request content: ", table.concat(bytes, " "))
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
failed to create OCSP request: no issuer certificate in chain

--- no_error_log
[alert]
[emerg]



=== TEST 23: validate good OCSP response
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local f = assert(io.open("t/cert/ocsp/ocsp-resp.der"))
            local resp = f:read("*a")
            f:close()

            local req, err = ssl.validate_ocsp_response(resp, cert_data)
            if not req then
                ngx.log(ngx.ERR, "failed to validate OCSP response: ", err)
                return
            end

            ngx.log(ngx.WARN, "OCSP response validation ok")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
OCSP response validation ok

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 24: fail to validate OCSP response - no issuer cert
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/test-com.crt"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local f = assert(io.open("t/cert/ocsp/ocsp-resp.der"))
            local resp = f:read("*a")
            f:close()

            local req, err = ssl.validate_ocsp_response(resp, cert_data)
            if not req then
                ngx.log(ngx.ERR, "failed to validate OCSP response: ", err)
                return
            end

            ngx.log(ngx.WARN, "OCSP response validation ok")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
failed to validate OCSP response: no issuer certificate in chain

--- no_error_log
OCSP response validation ok
[alert]
[emerg]



=== TEST 25: validate good OCSP response - no certs in response
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local f = assert(io.open("t/cert/ocsp/ocsp-resp-no-certs.der"))
            local resp = f:read("*a")
            f:close()

            local req, err = ssl.validate_ocsp_response(resp, cert_data)
            if not req then
                ngx.log(ngx.ERR, "failed to validate OCSP response: ", err)
                return
            end

            ngx.log(ngx.WARN, "OCSP response validation ok")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
OCSP response validation ok

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 26: validate OCSP response - OCSP response signed by an unknown cert and the OCSP response contains the unknown cert

FIXME: we should complain in this case.

--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local f = assert(io.open("t/cert/ocsp/ocsp-resp-signed-by-orphaned.der"))
            local resp = f:read("*a")
            f:close()

            local req, err = ssl.validate_ocsp_response(resp, cert_data)
            if not req then
                ngx.log(ngx.ERR, "failed to validate OCSP response: ", err)
                return
            end

            ngx.log(ngx.WARN, "OCSP response validation ok")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
OCSP response validation ok

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 27: fail to validate OCSP response - OCSP response signed by an unknown cert and the OCSP response does not contain the unknown cert

--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return
            end

            local f = assert(io.open("t/cert/ocsp/ocsp-resp-signed-by-orphaned-no-certs.der"))
            local resp = f:read("*a")
            f:close()

            local req, err = ssl.validate_ocsp_response(resp, cert_data)
            if not req then
                ngx.log(ngx.ERR, "failed to validate OCSP response: ", err)
                return
            end

            ngx.log(ngx.WARN, "OCSP response validation ok")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
failed to validate OCSP response: OCSP_basic_verify() failed

--- no_error_log
OCSP response validation ok
[alert]
[emerg]



=== TEST 28: fail to validate OCSP response - OCSP response returns revoked status
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/revoked-chain.pem"))
            local cert_data = f:read("*a")
            f:close()

            cert_data, err = ssl.cert_pem_to_der(cert_data)
            if not cert_data then
                ngx.log(ngx.ERR, "failed to convert pem cert to der cert: ", err)
                return ngx.exit(ngx.ERROR)
            end

            local f = assert(io.open("t/cert/ocsp/revoked-ocsp-resp.der"))
            local resp = f:read("*a")
            f:close()

            local req, err = ssl.validate_ocsp_response(resp, cert_data)
            if not req then
                ngx.log(ngx.ERR, "failed to validate OCSP response: ", err)
                return ngx.exit(ngx.ERROR)
            end

            ngx.log(ngx.WARN, "OCSP response validation ok")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log
lua ssl server name: "test.com"
failed to validate OCSP response: certificate status "revoked" in the OCSP response

--- no_error_log
OCSP response validation ok
[alert]
[emerg]



=== TEST 29: good status req from client
FIXME: check the OCSP staple actually received by the ssl client
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/ocsp-resp.der"))
            local resp = assert(f:read("*a"))
            f:close()

            print("resp len: ", #resp)

            local ok, err = ssl.set_ocsp_status_resp(resp)
            if not ok then
                ngx.log(ngx.ERR, "failed to set ocsp status resp: ", err)
                return
            end
            ngx.log(ngx.WARN, "ocsp status resp set ok: ", err)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true, true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
ocsp status resp set ok: nil,

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 30: no status req from client
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local f = assert(io.open("t/cert/ocsp/ocsp-resp.der"))
            local resp = assert(f:read("*a"))
            f:close()

            print("resp len: ", #resp)

            local ok, err = ssl.set_ocsp_status_resp(resp)
            if not ok then
                ngx.log(ngx.ERR, "failed to set ocsp status resp: ", err)
                return
            end
            ngx.log(ngx.WARN, "ocsp status resp set ok: ", err)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
ocsp status resp set ok: no status req,

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 31: tls version - SSLv3
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local ver, err = ssl.get_tls1_version_str(resp)
            if not ver then
                ngx.log(ngx.ERR, "failed to get TLS1 version: ", err)
                return
            end
            ngx.log(ngx.WARN, "got TLS1 version: ", ver)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        ssl_protocols SSLv3;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;
    lua_ssl_protocols SSLv3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean

--- error_log
got TLS1 version: SSLv3,

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 32: tls version - TLSv1
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local ver, err = ssl.get_tls1_version_str(resp)
            if not ver then
                ngx.log(ngx.ERR, "failed to get TLS1 version: ", err)
                return
            end
            ngx.log(ngx.WARN, "got TLS1 version: ", ver)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        ssl_protocols TLSv1;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;
    lua_ssl_protocols TLSv1;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean

--- error_log
got TLS1 version: TLSv1,

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 33: tls version - TLSv1.1
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local ver, err = ssl.get_tls1_version_str(resp)
            if not ver then
                ngx.log(ngx.ERR, "failed to get TLS1 version: ", err)
                return
            end
            ngx.log(ngx.WARN, "got TLS1 version: ", ver)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        ssl_protocols TLSv1.1;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;
    lua_ssl_protocols TLSv1.1;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean

--- error_log
got TLS1 version: TLSv1.1,

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 34: tls version - TLSv1.2
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            local ssl = require "ngx.ssl"

            local ver, err = ssl.get_tls1_version_str(resp)
            if not ver then
                ngx.log(ngx.ERR, "failed to get TLS1 version: ", err)
                return
            end
            ngx.log(ngx.WARN, "got TLS1 version: ", ver)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        ssl_protocols TLSv1.2;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;
    lua_ssl_protocols TLSv1.2;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean

--- error_log
got TLS1 version: TLSv1.2,

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 35: ngx.exit(0) - no yield
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            ngx.exit(0)
            ngx.log(ngx.ERR, "should never reached here...")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean

--- error_log
lua exit with code 0

--- no_error_log
should never reached here
[error]
[alert]
[emerg]



=== TEST 36: ngx.exit(ngx.ERROR) - no yield
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            ngx.exit(ngx.ERROR)
            ngx.log(ngx.ERR, "should never reached here...")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'lua_certificate_by_lua: handler return value: -1, cert cb exit code: 0',
qr/\[crit\] .*? SSL_do_handshake\(\) failed .*?cert cb error/,
'lua exit with code -1',
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 37: ngx.exit(0) -  yield
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            ngx.sleep(0.001)
            ngx.exit(0)

            ngx.log(ngx.ERR, "should never reached here...")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean

--- error_log
lua exit with code 0

--- no_error_log
should never reached here
[error]
[alert]
[emerg]



=== TEST 38: ngx.exit(ngx.ERROR) - yield
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            ngx.sleep(0.001)
            ngx.exit(ngx.ERROR)

            ngx.log(ngx.ERR, "should never reached here...")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'lua_certificate_by_lua: cert cb exit code: 0',
qr/\[crit\] .*? SSL_do_handshake\(\) failed .*?cert cb error/,
'lua exit with code -1',
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 39: lua exception - no yield
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            error("bad bad bad")
            ngx.log(ngx.ERR, "should never reached here...")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'runtime error: ssl_certificate_by_lua:2: bad bad bad',
'lua_certificate_by_lua: handler return value: 500, cert cb exit code: 0',
qr/\[crit\] .*? SSL_do_handshake\(\) failed .*?cert cb error/,
qr/context: ssl_certificate_by_lua\*, client: \d+\.\d+\.\d+\.\d+, server: \d+\.\d+\.\d+\.\d+:\d+/,
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 40: lua exception - yield
--- http_config
    lua_package_path "t/lib/?.lua;lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.2:8080 ssl;
        server_name test.com;
        ssl_certificate_by_lua '
            ngx.sleep(0.001)
            error("bad bad bad")
            ngx.log(ngx.ERR, "should never reached here...")
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", 8080)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        ';
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'runtime error: ssl_certificate_by_lua:3: bad bad bad',
'lua_certificate_by_lua: cert cb exit code: 0',
qr/\[crit\] .*? SSL_do_handshake\(\) failed .*?cert cb error/,
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 41: get phase
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua 'print("get_phase: ", ngx.get_phase())';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end
            collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- error_log
lua ssl server name: "test.com"
get_phase: ssl_cert

--- no_error_log
[error]
[alert]



=== TEST 42: connection aborted prematurely
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            ngx.sleep(0.4)
            local ssl = require "ngx.ssl"
            ssl.clear_certs()
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(300)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t

--- response_body
connected: 1
failed to do SSL handshake: timeout

--- error_log
lua ssl server name: "test.com"

--- no_error_log
[error]
[alert]



=== TEST 43: subrequests disabled
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua 'ngx.location.capture("/foo")';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'lua ssl server name: "test.com"',
'ssl_certificate_by_lua:1: API disabled in the context of ssl_certificate_by_lua*',
qr/\[crit\] .*?cert cb error/,
]

--- no_error_log
[alert]



=== TEST 44: simple logging (by_lua_file)
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_file html/a.lua;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }

--- user_files
>>> a.lua
print("ssl cert by lua is running!")

--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
a.lua:1: ssl cert by lua is running!

--- no_error_log
[error]
[alert]



=== TEST 45: coroutine API
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

            local function f()
                local cnt = 0
                for i = 1, 20 do
                    print("co yield: ", cnt)
                    cy()
                    cnt = cnt + 1
                end
            end

            local c = cc(f)
            for i = 1, 3 do
                print("co resume, status: ", coroutine.status(c))
                cr(c)
            end
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- grep_error_log eval: qr/co (?:yield: \d+|resume, status: \w+)/
--- grep_error_log_out
co resume, status: suspended
co yield: 0
co resume, status: suspended
co yield: 1
co resume, status: suspended
co yield: 2

--- error_log
lua ssl server name: "test.com"

--- no_error_log
[error]
[alert]



=== TEST 46: simple user thread wait with yielding
--- http_config
    lua_package_path "lua/?.lua;../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua '
            function f()
                ngx.sleep(0.01)
                print("uthread: hello in thread")
                return "done"
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.log(ngx.ERR, "uthread: failed to spawn thread: ", err)
                return ngx.exit(ngx.ERROR)
            end

            print("uthread: thread created: ", coroutine.status(t))

            local ok, res = ngx.thread.wait(t)
            if not ok then
                print("uthread: failed to wait thread: ", res)
                return
            end

            print("uthread: ", res)
        ';
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua 'ngx.status = 201 ngx.say("foo") ngx.exit(201)';
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua '
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\\r\\nHost: test.com\\r\\nConnection: close\\r\\n\\r\\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to recieve response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        ';
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- no_error_log
[error]
[alert]
--- grep_error_log eval: qr/uthread: [^.,]+/
--- grep_error_log_out
uthread: thread created: running
uthread: hello in thread
uthread: done
