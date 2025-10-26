# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(3);

# All these tests need to have new openssl
my $NginxBinary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $openssl_version = eval { `$NginxBinary -V 2>&1` };

if ($openssl_version =~ m/built with OpenSSL (0\S*|1\.0\S*|1\.1\.0\S*)/) {
    plan(skip_all => "too old OpenSSL, need >= 1.1.1, was $1");
} elsif ($openssl_version =~ m/running with BoringSSL/) {
    plan(skip_all => "does not support BoringSSL");
} elsif ($ENV{TEST_NGINX_USE_HTTP3}) {
    plan tests => repeat_each() * (blocks() * 6 + 6);
} else {
    plan tests => repeat_each() * (blocks() * 6 + 10);
}

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_QUIC_IDLE_TIMEOUT} ||= 0.6;

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: simple logging
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_client_hello_by_lua_block { print("ssl client hello by lua is running!") }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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
--- grep_error_log eval: qr/ssl_client_hello_by_lua\(.*?,|\bssl client hello: connection reusable: \d+|\breusable connection: \d+/
--- grep_error_log_out eval
# Since nginx version 1.17.9, nginx call ngx_reusable_connection(c, 0)
# before call ssl callback function
$Test::Nginx::Util::NginxVersion >= 1.017009 ?
qr/reusable connection: 0
ssl client hello: connection reusable: 0
ssl_client_hello_by_lua\(nginx.conf:\d+\):1: ssl client hello by lua is running!,/
: qr /reusable connection: 1
ssl client hello: connection reusable: 1
reusable connection: 0
ssl_client_hello_by_lua\(nginx.conf:\d+\):1: ssl client hello by lua is running!,/



=== TEST 2: sleep
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_client_hello_by_lua_block {
            local begin = ngx.now()
            ngx.sleep(0.1)
            print("elapsed in ssl client hello by lua: ", ngx.now() - begin)
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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
qr/elapsed in ssl client hello by lua: 0.(?:09|1\d)\d+,/,
]

--- no_error_log
[error]
[alert]



=== TEST 3: timer
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_client_hello_by_lua_block {
            local function f()
                print("my timer run!")
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to create timer: ", err)
                return
            end
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_client_hello_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect to memc: ", err)
                return
            end

            local bytes, err = sock:send("flush_all\r\n")
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
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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



=== TEST 5: ngx.exit(0) - no yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_client_hello_by_lua_block {
            ngx.exit(0)
            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
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
        }
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



=== TEST 6: ngx.exit(ngx.ERROR) - no yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_client_hello_by_lua_block {
            ngx.exit(ngx.ERROR)
            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
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
        }
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'ssl_client_hello_by_lua: handler return value: -1, client hello cb exit code: 0',
qr/\[info\] .*? SSL_do_handshake\(\) failed .*?callback failed/,
'lua exit with code -1',
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 7: ngx.exit(0) -  yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_client_hello_by_lua_block {
            ngx.sleep(0.001)
            ngx.exit(0)

            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
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
        }
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



=== TEST 8: ngx.exit(ngx.ERROR) - yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_client_hello_by_lua_block {
            ngx.sleep(0.001)
            ngx.exit(ngx.ERROR)

            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
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
        }
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'ssl_client_hello_by_lua: client hello cb exit code: 0',
qr/\[info\] .*? SSL_do_handshake\(\) failed .*?callback failed/,
'lua exit with code -1',
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 9: lua exception - no yield
--- http_config
    server {
        listen 127.0.0.2:$TEST_NGINX_RAND_PORT_2 ssl;
        server_name test.com;
        ssl_client_hello_by_lua_block {
            error("bad bad bad")
            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", $TEST_NGINX_RAND_PORT_2)
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
        }
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'runtime error: ssl_client_hello_by_lua(nginx.conf:28):2: bad bad bad',
'ssl_client_hello_by_lua: handler return value: 500, client hello cb exit code: 0',
qr/\[info\] .*? SSL_do_handshake\(\) failed .*?callback failed/,
qr/context: ssl_client_hello_by_lua\*, client: \d+\.\d+\.\d+\.\d+, server: \d+\.\d+\.\d+\.\d+:\d+/,
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 10: lua exception - yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_client_hello_by_lua_block {
            ngx.sleep(0.001)
            error("bad bad bad")
            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
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
        }
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'runtime error: ssl_client_hello_by_lua(nginx.conf:28):3: bad bad bad',
'ssl_client_hello_by_lua: client hello cb exit code: 0',
qr/\[info\] .*? SSL_do_handshake\(\) failed .*?callback failed/,
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 11: get phase
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_client_hello_by_lua_block {print("get_phase: ", ngx.get_phase())}
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata

--- error_log
lua ssl server name: "test.com"
get_phase: ssl_client_hello

--- no_error_log
[error]
[alert]



=== TEST 12: connection aborted prematurely
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_client_hello_by_lua_block {
            ngx.sleep(0.3)
            print("ssl-client-hello-by-lua: after sleeping")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(150)

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
        }
    }

--- request
GET /t

--- response_body
connected: 1
failed to do SSL handshake: timeout

--- error_log
lua ssl server name: "test.com"
ssl-client-hello-by-lua: after sleeping

--- no_error_log
[error]
[alert]
--- wait: 0.6



=== TEST 13: subrequests disabled
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_client_hello_by_lua_block {ngx.location.capture("/foo")}
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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
        }
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'lua ssl server name: "test.com"',
'ssl_client_hello_by_lua(nginx.conf:28):1: API disabled in the context of ssl_client_hello_by_lua*',
qr/\[info\] .*?callback failed/,
]

--- no_error_log
[alert]



=== TEST 14: simple logging (by_lua_file)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_client_hello_by_lua_file html/a.lua;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }

--- user_files
>>> a.lua
print("ssl client hello by lua is running!")

--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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
a.lua:1: ssl client hello by lua is running!

--- no_error_log
[error]
[alert]



=== TEST 15: coroutine API
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_client_hello_by_lua_block {
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
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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



=== TEST 16: simple user thread wait with yielding
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_client_hello_by_lua_block {
            local function f()
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
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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



=== TEST 17: simple logging - use ssl_client_hello_by_lua* on the http {} level
GitHub openresty/lua-resty-core#42
--- http_config
    ssl_client_hello_by_lua_block { print("ssl client hello by lua is running!") }
    ssl_certificate ../../cert/test.crt;
    ssl_certificate_key ../../cert/test.key;

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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
ssl_client_hello_by_lua(nginx.conf:25):1: ssl client hello by lua is running!

--- no_error_log
[error]
[alert]



=== TEST 18: simple logging - use ssl_client_hello_by_lua* on the http {} level and server {} level
--- http_config
    ssl_client_hello_by_lua_block { print("ssl client hello by lua on the http level is running!") }
    ssl_certificate ../../cert/test.crt;
    ssl_certificate_key ../../cert/test.key;

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_client_hello_by_lua_block { print("ssl client hello by lua on the server level is running!") }
        server_name   test.com;
        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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
ssl_client_hello_by_lua(nginx.conf:31):1: ssl client hello by lua on the server level is running!

--- no_error_log
[error]
[alert]



=== TEST 19: use ssl_client_hello_by_lua* on the server {} level with non-ssl server
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        ssl_client_hello_by_lua_block { print("ssl client hello by lua is running!") }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        server_name   test.com;
        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
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
ssl client hello by lua is running!
[error]
[alert]



=== TEST 20: use ssl_client_hello_by_lua* on the http {} level with non-ssl server
--- http_config
    ssl_certificate ../../cert/test.crt;
    ssl_certificate_key ../../cert/test.key;
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        ssl_client_hello_by_lua_block { print("ssl client hello by lua is running!") }
        server_name   test.com;
        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
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
ssl client hello by lua is running!
[error]
[alert]



=== TEST 21: listen two ports (one for ssl and one for non-ssl) in one server - connect ssl port
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        listen unix:$TEST_NGINX_HTML_DIR/nginx2.sock;
        ssl_client_hello_by_lua_block { print("ssl client hello by lua is running!") }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        server_name   test.com;
        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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
ssl_client_hello_by_lua(nginx.conf:28):1: ssl client hello by lua is running!

--- no_error_log
[error]
[alert]



=== TEST 22: listen two ports (one for ssl and one for non-ssl) in one server - connect non-ssl port
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        listen unix:$TEST_NGINX_HTML_DIR/nginx2.sock;
        ssl_client_hello_by_lua_block { print("ssl client hello by lua is running!") }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        server_name   test.com;
        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx2.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
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
ssl client hello by lua is running!
[error]
[alert]



=== TEST 23: simple logging - use ssl_client_hello_by_lua* in multiple virtual servers
--- http_config
    ssl_certificate ../../cert/test.crt;
    ssl_certificate_key ../../cert/test.key;
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_client_hello_by_lua_block { print("ssl client hello by lua in server1 is running!") }
        server_name   test.com;
        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        ssl_client_hello_by_lua_block { print("ssl client hello by lua in server2 is running!") }
        server_name   test2.com;
        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo2") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test2.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
sent http request: 57 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 5
received: Connection: close
received: 
received: foo2
close: 1 nil

--- error_log
lua ssl server name: "test.com"
ssl_client_hello_by_lua(nginx.conf:29):1: ssl client hello by lua in server1 is running!

--- no_error_log
ssl client hello by lua in server2 is running!
[error]
[alert]



=== TEST 24: simple logging (syslog)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        error_log syslog:server=127.0.0.1:12345 debug;

        ssl_client_hello_by_lua_block { print("ssl client hello by lua is running!") }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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
qr/\[error\] .*? send\(\) failed/,
'lua ssl server name: "test.com"',
]
--- no_error_log
[alert]
ssl client hello by lua is running!



=== TEST 25: get raw_client_addr - IPv4
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1 ssl;
        server_name   test.com;

        ssl_client_hello_by_lua_block {
            local ssl = require "ngx.ssl"
            local byte = string.byte
            local addr, addrtype, err = ssl.raw_client_addr()
            local ip = string.format("%d.%d.%d.%d", byte(addr, 1), byte(addr, 2),
                       byte(addr, 3), byte(addr, 4))
            print("client ip: ", ip)
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_RAND_PORT_1)
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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
client ip: 127.0.0.1

--- no_error_log
[error]
[alert]



=== TEST 26: get raw_client_addr - unix domain socket
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_client_hello_by_lua_block {
            local ssl = require "ngx.ssl"
            local addr, addrtyp, err = ssl.raw_client_addr()
            print("client socket file: ", addr)
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
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
client socket file:

--- no_error_log
[error]
[alert]



=== TEST 27: ssl_client_hello_by_lua* can yield when reading early data
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        ssl_early_data on;
        server_tokens off;

        ssl_client_hello_by_lua_block {
            local begin = ngx.now()
            ngx.sleep(0.1)
            print("elapsed in ssl_client_hello_by_lua*: ", ngx.now() - begin)
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
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
        }
    }
--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean
--- grep_error_log eval
qr/elapsed in ssl_client_hello_by_lua\*: 0\.(?:09|1\d)\d+,/,
--- grep_error_log_out eval
[
qr/elapsed in ssl_client_hello_by_lua\*: 0\.(?:09|1\d)\d+,/,
qr/elapsed in ssl_client_hello_by_lua\*: 0\.(?:09|1\d)\d+,/,
qr/elapsed in ssl_client_hello_by_lua\*: 0\.(?:09|1\d)\d+,/,
]
--- no_error_log
[error]
[alert]
[emerg]



=== TEST 28: cosocket (UDP)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        server_tokens off;

        ssl_client_hello_by_lua_block {
            local sock = ngx.socket.udp()

            sock:settimeout(1000)

            local ok, err = sock:setpeername("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect to memc: ", err)
                return
            end

            local req = "\0\1\0\0\0\1\0\0flush_all\r\n"
            local ok, err = sock:send(req)
            if not ok then
                ngx.log(ngx.ERR, "failed to send flush_all to memc: ", err)
                return
            end

            local res, err = sock:receive()
            if not res then
                ngx.log(ngx.ERR, "failed to receive memc reply: ", err)
                return
            end

            ngx.log(ngx.INFO, "received memc reply of ", #res, " bytes")
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
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
        }
    }
--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
--- no_error_log
[error]
[alert]
[emerg]
--- grep_error_log eval: qr/received memc reply of \d+ bytes/
--- grep_error_log_out eval
[
'received memc reply of 12 bytes
',
'received memc reply of 12 bytes
',
'received memc reply of 12 bytes
',
'received memc reply of 12 bytes
',
]



=== TEST 29: uthread (kill)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        server_tokens off;

        ssl_client_hello_by_lua_block {
            local function f()
                ngx.log(ngx.INFO, "uthread: hello from f()")
                ngx.sleep(1)
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.log(ngx.ERR, "failed to spawn thread: ", err)
                return ngx.exit(ngx.ERROR)
            end

            local ok, res = ngx.thread.kill(t)
            if not ok then
                ngx.log(ngx.ERR, "failed to kill thread: ", res)
                return
            end

            ngx.log(ngx.INFO, "uthread: killed")

            local ok, err = ngx.thread.kill(t)
            if not ok then
                ngx.log(ngx.INFO, "uthread: failed to kill: ", err)
            end
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
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
        }
    }
--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
--- no_error_log
[error]
[alert]
[emerg]
--- grep_error_log eval: qr/uthread: [^.,]+/
--- grep_error_log_out
uthread: hello from f()
uthread: killed
uthread: failed to kill: already waited or killed



=== TEST 30: ngx.exit(ngx.OK) - no yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_client_hello_by_lua_block {
            ngx.exit(ngx.OK)
            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
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
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean

--- error_log eval
[
'ssl_client_hello_by_lua: handler return value: 0, client hello cb exit code: 1',
qr/\[debug\] .*? SSL_do_handshake: 1/,
'lua exit with code 0',
]
--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 31: ssl_client_hello_by_lua* can yield when reading early data
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("ssl client hello by lua is running!")
        ngx.sleep(0.1)
        print("ssl client hello by lua is done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(ssl client hello by lua is running!|ssl client hello by lua is done|test completed)/
--- grep_error_log_out
ssl client hello by lua is running!
ssl client hello by lua is done
test completed
--- no_error_log
[error]
[alert]
[emerg]



=== TEST 32: ssl_client_hello_by_lua* with TCP cosocket (yield API)
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("ssl client hello: TCP cosocket test start")

        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if not ok then
            ngx.log(ngx.ERR, "failed to connect to memc: ", err)
            return
        end

        local bytes, err = sock:send("flush_all\r\n")
        if not bytes then
            ngx.log(ngx.ERR, "failed to send flush_all command: ", err)
            return
        end

        local res, err = sock:receive()
        if not res then
            ngx.log(ngx.ERR, "failed to receive memc reply: ", err)
            return
        end

        print("ssl client hello: received TCP memc reply: ", res)
        sock:close()
        print("ssl client hello: TCP cosocket test done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(ssl client hello: TCP cosocket test start|ssl client hello: received TCP memc reply: OK|ssl client hello: TCP cosocket test done|test completed)/
--- grep_error_log_out
ssl client hello: TCP cosocket test start
ssl client hello: received TCP memc reply: OK
ssl client hello: TCP cosocket test done
test completed

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 33: ssl_client_hello_by_lua* with UDP cosocket (yield API)
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("ssl client hello: UDP cosocket test start")

        local sock = ngx.socket.udp()
        sock:settimeout(1000)

        local ok, err = sock:setpeername("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if not ok then
            ngx.log(ngx.ERR, "failed to connect to memc: ", err)
            return
        end

        local req = "\0\1\0\0\0\1\0\0flush_all\r\n"
        local ok, err = sock:send(req)
        if not ok then
            ngx.log(ngx.ERR, "failed to send flush_all to memc: ", err)
            return
        end

        local res, err = sock:receive()
        if not res then
            ngx.log(ngx.ERR, "failed to receive memc reply: ", err)
            return
        end

        print("ssl client hello: received UDP memc reply of ", #res, " bytes")
        sock:close()
        print("ssl client hello: UDP cosocket test done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(ssl client hello: UDP cosocket test start|ssl client hello: received UDP memc reply of \d+ bytes|ssl client hello: UDP cosocket test done|test completed)/
--- grep_error_log_out
ssl client hello: UDP cosocket test start
ssl client hello: received UDP memc reply of 12 bytes
ssl client hello: UDP cosocket test done
test completed

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 34: ssl_client_hello_by_lua* with ngx.timer (yield API)
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("ssl client hello: timer test start")

        local function timer_handler()
            print("ssl client hello: timer executed")
        end

        local ok, err = ngx.timer.at(0, timer_handler)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
            return
        end

        print("ssl client hello: timer created")
        print("ssl client hello: timer test done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(ssl client hello: timer test start|ssl client hello: timer created|ssl client hello: timer test done|ssl client hello: timer executed|test completed)/
--- grep_error_log_out
ssl client hello: timer test start
ssl client hello: timer created
ssl client hello: timer test done
ssl client hello: timer executed
test completed

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 35: ssl_client_hello_by_lua* with user threads (yield API)
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("ssl client hello: uthread test start")

        local function worker()
            ngx.sleep(0.01)
            print("ssl client hello: uthread worker executed")
            return "worker_result"
        end

        local t, err = ngx.thread.spawn(worker)
        if not t then
            ngx.log(ngx.ERR, "failed to spawn thread: ", err)
            return
        end

        print("ssl client hello: uthread spawned")

        local ok, res = ngx.thread.wait(t)
        if not ok then
            ngx.log(ngx.ERR, "failed to wait thread: ", res)
            return
        end

        print("ssl client hello: uthread result: ", res)
        print("ssl client hello: uthread test done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(ssl client hello: uthread test start|ssl client hello: uthread spawned|ssl client hello: uthread worker executed|ssl client hello: uthread result: worker_result|ssl client hello: uthread test done|test completed)/
--- grep_error_log_out
ssl client hello: uthread test start
ssl client hello: uthread spawned
ssl client hello: uthread worker executed
ssl client hello: uthread result: worker_result
ssl client hello: uthread test done
test completed

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 36: ssl_client_hello_by_lua* with coroutines (yield API)
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("ssl client hello: coroutine test start")

        local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

        local function coro_func()
            local cnt = 0
            for i = 1, 3 do
                print("ssl client hello: coro yield: ", cnt)
                cy()
                cnt = cnt + 1
            end
            return "coro_done"
        end

        local c = cc(coro_func)
        for i = 1, 4 do
            print("ssl client hello: coro resume, status: ", coroutine.status(c))
            local ok, res = cr(c)
            if not ok then
                print("ssl client hello: coro error: ", res)
                break
            end
            if coroutine.status(c) == "dead" then
                print("ssl client hello: coro result: ", res)
                break
            end
        end

        print("ssl client hello: coroutine test done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(ssl client hello: coroutine test start|ssl client hello: coro resume, status: \w+|ssl client hello: coro yield: \d+|ssl client hello: coro result: coro_done|ssl client hello: coroutine test done|test completed)/
--- grep_error_log_out
ssl client hello: coroutine test start
ssl client hello: coro resume, status: suspended
ssl client hello: coro yield: 0
ssl client hello: coro resume, status: suspended
ssl client hello: coro yield: 1
ssl client hello: coro resume, status: suspended
ssl client hello: coro yield: 2
ssl client hello: coro resume, status: suspended
ssl client hello: coro result: coro_done
ssl client hello: coroutine test done
test completed

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 37: ssl_client_hello_by_lua* without yield API (simple logic)
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("ssl client hello: simple test start")

        -- Simple calculations without yield
        local sum = 0
        for i = 1, 10 do
            sum = sum + i
        end

        print("ssl client hello: calculated sum: ", sum)

        -- String operations
        local str = "hello"
        str = str .. " world"
        print("ssl client hello: concatenated string: ", str)

        -- Table operations
        local t = {a = 1, b = 2, c = 3}
        local count = 0
        for k, v in pairs(t) do
            count = count + v
        end
        print("ssl client hello: table sum: ", count)

        print("ssl client hello: simple test done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(ssl client hello: simple test start|ssl client hello: calculated sum: 55|ssl client hello: concatenated string: hello world|ssl client hello: table sum: 6|ssl client hello: simple test done|test completed)/
--- grep_error_log_out
ssl client hello: simple test start
ssl client hello: calculated sum: 55
ssl client hello: concatenated string: hello world
ssl client hello: table sum: 6
ssl client hello: simple test done
test completed

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 38: ssl_client_hello_by_lua* with multiple network operations (yield API)
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("ssl client hello: multiple network test start")

        -- First TCP operation
        local sock1 = ngx.socket.tcp()
        sock1:settimeout(2000)
        local ok, err = sock1:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if ok then
            local bytes, err = sock1:send("version\r\n")
            if bytes then
                local res, err = sock1:receive()
                if res then
                    print("ssl client hello: TCP1 version: ", res)
                end
            end
            sock1:close()
        end

        ngx.sleep(0.01)  -- Small delay

        -- Second UDP operation
        local sock2 = ngx.socket.udp()
        sock2:settimeout(1000)
        local ok, err = sock2:setpeername("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if ok then
            local req = "\0\1\0\0\0\1\0\0version\r\n"
            local ok, err = sock2:send(req)
            if ok then
                local res, err = sock2:receive()
                if res then
                    print("ssl client hello: UDP version reply length: ", #res)
                end
            end
            sock2:close()
        end

        print("ssl client hello: multiple network test done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(ssl client hello: multiple network test start|ssl client hello: TCP1 version: VERSION|ssl client hello: UDP version reply length: \d+|ssl client hello: multiple network test done|test completed)/
--- grep_error_log_out eval
[
qr/ssl client hello: multiple network test start/,
qr/ssl client hello: TCP1 version: VERSION/,
qr/ssl client hello: UDP version reply length: \d+/,
qr/ssl client hello: multiple network test done/,
qr/test completed/,
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 39: ssl_cert_by_lua* and ssl_client_hello_by_lua* with sleep (yield API)
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- http_config
    ssl_certificate_by_lua_block {
        print("cert by: starting with sleep")
        local begin = ngx.now()
        ngx.sleep(0.05)
        print("cert by: slept for ", ngx.now() - begin, " seconds")
    }

--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("client hello: starting with sleep")
        local begin = ngx.now()
        ngx.sleep(0.1)
        print("client hello: slept for ", ngx.now() - begin, " seconds")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(client hello: starting with sleep|client hello: slept for 0\.\d+|cert by: starting with sleep|cert by: slept for 0\.\d+|test completed)/
--- grep_error_log_out eval
[
qr/client hello: starting with sleep/,
qr/client hello: slept for 0\.(?:09|1\d)\d+/,
qr/cert by: starting with sleep/,
qr/cert by: slept for 0\.0[4-6]\d+/,
qr/test completed/,
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 40: ssl_cert_by_lua* and ssl_client_hello_by_lua* with cosocket (yield API)
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- http_config
    ssl_certificate_by_lua_block {
        print("cert by: cosocket test start")

        local sock = ngx.socket.udp()
        sock:settimeout(1000)

        local ok, err = sock:setpeername("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if not ok then
            ngx.log(ngx.ERR, "cert by: failed to connect to memc: ", err)
            return
        end

        local req = "\0\1\0\0\0\1\0\0flush_all\r\n"
        local ok, err = sock:send(req)
        if not ok then
            ngx.log(ngx.ERR, "cert by: failed to send flush_all to memc: ", err)
            return
        end

        local res, err = sock:receive()
        if not res then
            ngx.log(ngx.ERR, "cert by: failed to receive memc reply: ", err)
            return
        end

        print("cert by: received UDP memc reply of ", #res, " bytes")
        sock:close()
        print("cert by: cosocket test done")
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("client hello: cosocket test start")

        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if not ok then
            ngx.log(ngx.ERR, "client hello: failed to connect to memc: ", err)
            return
        end

        local bytes, err = sock:send("version\r\n")
        if not bytes then
            ngx.log(ngx.ERR, "client hello: failed to send version command: ", err)
            return
        end

        local res, err = sock:receive()
        if not res then
            ngx.log(ngx.ERR, "client hello: failed to receive memc reply: ", err)
            return
        end

        print("client hello: received memc reply: ", res)
        sock:close()
        print("client hello: cosocket test done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(client hello: cosocket test start|client hello: received memc reply: VERSION|client hello: cosocket test done|cert by: cosocket test start|cert by: received UDP memc reply of \d+ bytes|cert by: cosocket test done|test completed)/
--- grep_error_log_out eval
[
qr/client hello: cosocket test start/,
qr/client hello: received memc reply: VERSION/,
qr/client hello: cosocket test done/,
qr/cert by: cosocket test start/,
qr/cert by: received UDP memc reply of \d+ bytes/,
qr/cert by: cosocket test done/,
qr/test completed/,
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 41: ssl_cert_by_lua* and ssl_client_hello_by_lua* with timer and uthread (yield API)
--- skip_eval: 6:!$ENV{TEST_NGINX_USE_HTTP3}
--- http_config
    ssl_certificate_by_lua_block {
        print("cert by: coroutine test start")

        local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

        local function coro_func()
            local cnt = 0
            for i = 1, 2 do
                print("cert by: coro yield: ", cnt)
                cy()
                cnt = cnt + 1
            end
            return "cert_by_coro_done"
        end

        local c = cc(coro_func)
        for i = 1, 3 do
            print("cert by: coro resume, status: ", coroutine.status(c))
            local ok, res = cr(c)
            if not ok then
                print("cert by: coro error: ", res)
                break
            end
            if coroutine.status(c) == "dead" then
                print("cert by: coro result: ", res)
                break
            end
        end

        -- Small sleep to allow timer to execute
        ngx.sleep(0.01)
        print("cert by: coroutine test done")
    }

--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("client hello: timer and uthread test start")

        -- Timer test
        local function timer_handler()
            print("client hello: timer executed")
        end

        local ok, err = ngx.timer.at(0, timer_handler)
        if not ok then
            ngx.log(ngx.ERR, "client hello: failed to create timer: ", err)
            return
        end

        print("client hello: timer created")

        -- User thread test
        local function worker()
            ngx.sleep(0.01)
            print("client hello: uthread worker executed")
            return "client_hello_result"
        end

        local t, err = ngx.thread.spawn(worker)
        if not t then
            ngx.log(ngx.ERR, "client hello: failed to spawn thread: ", err)
            return
        end

        print("client hello: uthread spawned")

        local ok, res = ngx.thread.wait(t)
        if not ok then
            ngx.log(ngx.ERR, "client hello: failed to wait thread: ", res)
            return
        end

        print("client hello: uthread result: ", res)
        print("client hello: timer and uthread test done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- response_body
test completed

--- grep_error_log eval: qr/(client hello: timer and uthread test start|client hello: timer created|client hello: uthread spawned|client hello: uthread worker executed|client hello: uthread result: client_hello_result|client hello: timer and uthread test done|cert by: coroutine test start|cert by: coro resume, status: \w+|cert by: coro yield: \d+|cert by: coro result: cert_by_coro_done|cert by: coroutine test done|client hello: timer executed|test completed)/
--- grep_error_log_out eval
[
qr/client hello: timer and uthread test start/,
qr/client hello: timer created/,
qr/client hello: uthread spawned/,
qr/client hello: uthread worker executed/,
qr/client hello: uthread result: client_hello_result/,
qr/client hello: timer and uthread test done/,
qr/cert by: coroutine test start/,
qr/cert by: coro resume, status: suspended/,
qr/cert by: coro yield: 0/,
qr/cert by: coro resume, status: suspended/,
qr/cert by: coro yield: 1/,
qr/cert by: coro resume, status: suspended/,
qr/cert by: coro result: cert_by_coro_done/,
qr/cert by: coroutine test done/,
qr/client hello: timer executed/,
qr/test completed/,
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 42: ssl_cert_by_lua* with cosocket (yield API) and ssl_client_hello_by_lua* failure
--- skip_eval: 8:!$ENV{TEST_NGINX_USE_HTTP3}
--- http_config
    ssl_certificate_by_lua_block {
        print("cert by: test start")
        ngx.exit(500)
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    ssl_client_hello_by_lua_block {
        print("client hello: cosocket test start")

        local sock = ngx.socket.tcp()
        sock:settimeout(2000)

        local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if not ok then
            ngx.log(ngx.ERR, "client hello: failed to connect to memc: ", err)
            return
        end

        local bytes, err = sock:send("version\r\n")
        if not bytes then
            ngx.log(ngx.ERR, "client hello: failed to send version command: ", err)
            return
        end

        local res, err = sock:receive()
        if not res then
            ngx.log(ngx.ERR, "client hello: failed to receive memc reply: ", err)
            return
        end

        print("client hello: received memc reply: ", res)
        sock:close()
        print("client hello: cosocket test done")
    }

    location /t {
        content_by_lua_block {
            print("test completed")
            ngx.say("test completed")
        }
    }
--- request
GET /t
--- ignore_response
--- curl_error eval
qr/Connection time/
--- grep_error_log eval: qr/(client hello: cosocket test start|client hello: received memc reply: VERSION|client hello: cosocket test done|cert by: test start)/
--- grep_error_log_out eval
[
qr/client hello: cosocket test start/,
qr/client hello: received memc reply: VERSION/,
qr/client hello: cosocket test done/,
qr/cert by: test start/,
]

--- no_error_log
[error]
[alert]
[emerg]
