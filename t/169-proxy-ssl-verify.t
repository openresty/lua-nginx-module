# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(3);

# All these tests need to have new openssl
my $NginxBinary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $openssl_version = eval { `$NginxBinary -V 2>&1` };

if ($openssl_version =~ m/built with OpenSSL (0\S*|1\.0\S*|1\.1\.0\S*)/) {
    plan(skip_all => "too old OpenSSL, need 1.1.1, was $1");
} elsif ($openssl_version =~ m/running with BoringSSL/) {
    plan(skip_all => "does not support BoringSSL");
} elsif ($ENV{TEST_NGINX_USE_HTTP3}) {
    plan tests => repeat_each() * (blocks() * 6 + 6);
} else {
    plan tests => repeat_each() * (blocks() * 5 + 10);
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

=== TEST 1: invalid proxy_pass url
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("hello world")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                  http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        proxy_ssl_verify_by_lua_block {
            ngx.log(ngx.INFO, "hello world")
        }
    }
--- request
GET /t
--- error_log
proxy_ssl_verify_by_lua* should be used with proxy_pass https url
--- must_die



=== TEST 2: proxy_ssl_verify_by_lua in http {} block
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("hello world")
            }

            more_clear_headers Date;
        }
    }

    proxy_ssl_verify_by_lua_block {
        ngx.log(ngx.INFO, "hello world")
    }
--- config
    location /t {
        proxy_pass                  http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- error_log
"proxy_ssl_verify_by_lua_block" directive is not allowed here
--- must_die



=== TEST 3: proxy_ssl_verify_by_lua in server {} block
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("hello world")
            }

            more_clear_headers Date;
        }
    }

--- config
    proxy_ssl_verify_by_lua_block {
        ngx.log(ngx.INFO, "hello world")
    }

    location /t {
        proxy_pass                  http://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
    }
--- request
GET /t
--- error_log
"proxy_ssl_verify_by_lua_block" directive is not allowed here
--- must_die



=== TEST 4: simple logging
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("simple logging return")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;

        proxy_ssl_verify_by_lua_block {
            ngx.log(ngx.INFO, "proxy ssl verify by lua is running!")
        }
    }
--- request
GET /t
--- response_body
simple logging return
--- error_log
proxy ssl verify by lua is running!
--- no_error_log
[error]
[alert]



=== TEST 5: sleep
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("sleep")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;

        proxy_ssl_verify_by_lua_block {
            local begin = ngx.now()
            ngx.sleep(0.1)
            print("elapsed in proxy ssl verify by lua: ", ngx.now() - begin)
        }
    }
--- request
GET /t
--- response_body
sleep
--- error_log eval
qr/elapsed in proxy ssl verify by lua: 0.(?:09|1\d)\d+ while loading proxy ssl verify by lua,/,
--- no_error_log
[error]
[alert]



=== TEST 6: timer
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("timer")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;

        proxy_ssl_verify_by_lua_block {
            local function f()
                print("my timer run!")
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to create timer: ", err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
timer
--- error_log
my timer run!
--- no_error_log
[error]
[alert]



=== TEST 7: ngx.exit(0) - no yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("ngx.exit(0) no yield")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;

        proxy_ssl_verify_by_lua_block {
            ngx.exit(0)
            ngx.log(ngx.ERR, "should never reached here...")
        }
    }
--- request
GET /t
--- response_body
ngx.exit(0) no yield
--- error_log
lua exit with code 0
--- no_error_log
should never reached here
[error]
[alert]
[emerg]



=== TEST 8: ngx.exit(ngx.ERROR) - no yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("ngx.exit(ngx.ERROR) no yield")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
            ngx.exit(ngx.ERROR)
            ngx.log(ngx.ERR, "should never reached here...")
        }
    }
--- request
GET /t
--- error_code: 502
--- error_log eval
[
'lua exit with code -1',
'proxy_ssl_verify_by_lua: handler return value: -1, cert verify callback exit code: 0',
qr/.*? SSL_do_handshake\(\) failed .*?certificate verify failed/,
]
--- no_error_log
should never reached here
[error]
[alert]
[emerg]



=== TEST 9: ngx.exit(0) -  yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("ngx.exit(0) yield")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
            ngx.sleep(0.001)
            ngx.exit(0)

            ngx.log(ngx.ERR, "should never reached here...")
        }
    }
--- request
GET /t
--- response_body
ngx.exit(0) yield
--- error_log
lua exit with code 0
--- no_error_log
should never reached here
[error]
[alert]
[emerg]



=== TEST 10: ngx.exit(ngx.ERROR) - yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("ngx.exit(ngx.ERROR) yield")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
            ngx.sleep(0.001)
            ngx.exit(ngx.ERROR)

            ngx.log(ngx.ERR, "should never reached here...")
        }
    }
--- request
GET /t
--- error_code: 502
--- error_log eval
[
'lua exit with code -1',
'proxy_ssl_verify_by_lua: cert verify callback exit code: 0',
qr/.*? SSL_do_handshake\(\) failed .*?certificate verify failed/,
]
--- no_error_log
should never reached here
[error]
[alert]
[emerg]



=== TEST 11: lua exception - no yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("lua exception - no yield")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
            error("bad bad bad")
            ngx.log(ngx.ERR, "should never reached here...")
        }
    }
--- request
GET /t
--- error_code: 502
--- error_log eval
[
'runtime error: proxy_ssl_verify_by_lua(nginx.conf:65):2: bad bad bad',
'proxy_ssl_verify_by_lua: handler return value: 500, cert verify callback exit code: 0',
qr/.*? SSL_do_handshake\(\) failed .*?certificate verify failed/,
]
--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 12: lua exception - yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("lua exception - yield")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
            ngx.sleep(0.001)
            error("bad bad bad")
            ngx.log(ngx.ERR, "should never reached here...")
        }
    }
--- request
GET /t
--- error_code: 502
--- error_log eval
[
'runtime error: proxy_ssl_verify_by_lua(nginx.conf:65):3: bad bad bad',
'proxy_ssl_verify_by_lua: cert verify callback exit code: 0',
qr/.*? SSL_do_handshake\(\) failed .*?certificate verify failed/,
]
--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 13: get phase
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("get phase return")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
            print("get_phase: ", ngx.get_phase())
        }
    }
--- request
GET /t
--- response_body
get phase return
--- error_log
get_phase: proxy_ssl_verify
--- no_error_log
[error]
[alert]



=== TEST 14: subrequests disabled
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("subrequests disabled")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
            ngx.location.capture("/foo")
        }
    }
--- request
GET /t
--- error_code: 502
--- error_log eval
[
'proxy_ssl_verify_by_lua(nginx.conf:65):2: API disabled in the context of proxy_ssl_verify_by_lua*',
'proxy_ssl_verify_by_lua: handler return value: 500, cert verify callback exit code: 0',
qr/.*? SSL_do_handshake\(\) failed .*?certificate verify failed/,
]
--- no_error_log
[alert]



=== TEST 15: simple logging (by_lua_file)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("simple logging by lua file")
            }

            more_clear_headers Date;
        }
    }
--- user_files
>>> a.lua
print("proxy ssl verify by lua is running!")

--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_file html/a.lua;
    }
--- request
GET /t
--- response_body
simple logging by lua file
--- error_log
a.lua:1: proxy ssl verify by lua is running!
--- no_error_log
[error]
[alert]



=== TEST 16: coroutine API
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("coroutine API")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
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
    }
--- request
GET /t
--- response_body
coroutine API
--- grep_error_log eval: qr/co (?:yield: \d+|resume, status: \w+)/
--- grep_error_log_out
co resume, status: suspended
co yield: 0
co resume, status: suspended
co yield: 1
co resume, status: suspended
co yield: 2
--- no_error_log
[error]
[alert]



=== TEST 17: simple user thread wait with yielding
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("simple user thread wait with yielding")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
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
    }
--- request
GET /t
--- response_body
simple user thread wait with yielding
--- no_error_log
[error]
[alert]
--- grep_error_log eval: qr/uthread: [^.,]+/
--- grep_error_log_out
uthread: thread created: running while loading proxy ssl verify by lua
uthread: hello in thread while loading proxy ssl verify by lua
uthread: done while loading proxy ssl verify by lua



=== TEST 18: uthread (kill)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("uthread (kill)")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
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
--- request
GET /t
--- response_body
uthread (kill)
--- no_error_log
[error]
[alert]
[emerg]
--- grep_error_log eval: qr/uthread: [^.,]+/
--- grep_error_log_out
uthread: hello from f() while loading proxy ssl verify by lua
uthread: killed while loading proxy ssl verify by lua
uthread: failed to kill: already waited or killed while loading proxy ssl verify by lua



=== TEST 19: ngx.exit(ngx.OK) - no yield
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("ngx.exit(ngx.OK) - no yield")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
            ngx.exit(ngx.OK)
            ngx.log(ngx.ERR, "should never reached here...")
        }
    }
--- request
GET /t
--- response_body
ngx.exit(ngx.OK) - no yield
--- error_log eval
[
'proxy_ssl_verify_by_lua: handler return value: 0, cert verify callback exit code: 1',
qr/\[debug\] .*? SSL_do_handshake: 1/,
'lua exit with code 0',
]
--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 20: proxy_ssl_verify_by_lua* without yield API (simple logic)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("without yield API, simple logic")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
            print("proxy ssl verify: simple test start")

            -- Simple calculations without yield
            local sum = 0
            for i = 1, 10 do
                sum = sum + i
            end

            print("proxy ssl verify: calculated sum: ", sum)

            -- String operations
            local str = "hello"
            str = str .. " world"
            print("proxy ssl verify: concatenated string: ", str)

            -- Table operations
            local t = {a = 1, b = 2, c = 3}
            local count = 0
            for k, v in pairs(t) do
                count = count + v
            end
            print("proxy ssl verify: table sum: ", count)

            print("proxy ssl verify: simple test done")
        }
    }
--- request
GET /t
--- response_body
without yield API, simple logic
--- grep_error_log eval: qr/(proxy ssl verify: simple test start|proxy ssl verify: calculated sum: 55|proxy ssl verify: concatenated string: hello world|proxy ssl verify: table sum: 6|proxy ssl verify: simple test done)/
--- grep_error_log_out
proxy ssl verify: simple test start
proxy ssl verify: calculated sum: 55
proxy ssl verify: concatenated string: hello world
proxy ssl verify: table sum: 6
proxy ssl verify: simple test done

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 21: lua_upstream_skip_openssl_default_verify default off
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("lua_upstream_skip_openssl_default_verify default off")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        proxy_ssl_verify_by_lua_block {
            ngx.log(ngx.INFO, "proxy ssl verify by lua is running!")
        }
    }
--- request
GET /t
--- error_log
proxy_ssl_verify_by_lua: openssl default verify
--- no_error_log
[error]
[alert]



=== TEST 22: lua_upstream_skip_openssl_default_verify on
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("lua_upstream_skip_openssl_default_verify default off")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_ssl_conf_command        VerifyMode Peer;

        lua_upstream_skip_openssl_default_verify on;

        proxy_ssl_verify_by_lua_block {
            ngx.log(ngx.INFO, "proxy ssl verify by lua is running!")
        }
    }
--- request
GET /t
--- response_body
lua_upstream_skip_openssl_default_verify default off
--- error_log
proxy ssl verify by lua is running!
--- no_error_log
proxy_ssl_verify_by_lua: openssl default verify
[error]
[alert]



=== TEST 23: ngx.ctx to pass data from downstream phase to upstream phase
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("simple logging return")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;

        rewrite_by_lua_block {
            ngx.ctx.greeting = "I am from rewrite phase"
        }

        proxy_ssl_verify_by_lua_block {
            ngx.log(ngx.INFO, "greeting: ", ngx.ctx.greeting)
        }
    }
--- request
GET /t
--- response_body
simple logging return
--- error_log
greeting: I am from rewrite phase
--- no_error_log
[error]
[alert]



=== TEST 24: upstream connection aborted
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate ../../cert/mtls_server.crt;
        ssl_certificate_key ../../cert/mtls_server.key;

        location / {
            default_type 'text/plain';

            content_by_lua_block {
                ngx.say("hello world")
            }

            more_clear_headers Date;
        }
    }
--- config
    location /t {
        proxy_pass                    https://unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        proxy_ssl_verify              on;
        proxy_ssl_name                example.com;
        proxy_ssl_certificate         ../../cert/mtls_client.crt;
        proxy_ssl_certificate_key     ../../cert/mtls_client.key;
        proxy_ssl_trusted_certificate ../../cert/mtls_ca.crt;
        proxy_ssl_session_reuse       off;
        proxy_connect_timeout         100ms;

        proxy_ssl_verify_by_lua_block {
            ngx.sleep(0.2)
        }
    }
--- request
GET /t
--- error_code: 504
--- response_body_like: 504 Gateway Time-out
--- error_log
upstream timed out (110: Connection timed out) while loading proxy ssl verify by lua
proxy_ssl_verify_by_lua: cert verify callback aborted
--- no_error_log
[alert]
--- wait: 0.5
