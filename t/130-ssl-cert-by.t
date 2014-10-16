# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket::Lua;

repeat_each(3);

plan tests => repeat_each() * (blocks() * 6 + 11);

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
                return
            end

            local f = assert(io.open("t/cert/ocsp/revoked-ocsp-resp.der"))
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
failed to validate OCSP response: certificate status "revoked" in the OCSP response

--- no_error_log
OCSP response validation ok
[alert]
[emerg]

