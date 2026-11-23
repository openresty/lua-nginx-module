# vim:set ft= ts=4 sw=4 et fdm=marker:
#
# Regression test: an ssl_client_hello_by_lua* or ssl_certificate_by_lua*
# handler must not have the QUIC connection it runs on drained under it.
#
# ngx_quic_new_connection() puts a new QUIC connection on the reusable
# queue before its handshake.  Once free connections drop to
# worker_connections / 16, the ngx_get_connection() that the handler makes
# for its fake connection runs ngx_drain_connections(), which closes the
# oldest reusable connection.  When the handshaking connection is the only
# reusable one, it is closed and freed right there, and its slot comes back
# zeroed as the fake connection: the handler then dereferences a NULL
# c->ssl and the worker segfaults.  TCP is not affected, since nginx takes
# a connection off the reusable queue before its TLS handshake.
#
# Each test fills the worker with plain HTTP connections parked in
# "reading client request line", which are not reusable, and then makes
# one HTTP/3 request, so that the handshaking QUIC connection is the only
# reusable connection when the handler runs.

BEGIN {
    my $nginx = $ENV{TEST_NGINX_BINARY} || 'nginx';
    my $v     = eval { `$nginx -V 2>&1` } // '';

    if ($v !~ /--with-http_v3_module/) {
        $SkipReason = "requires nginx built with --with-http_v3_module";

    } elsif ($v =~ /BoringSSL/) {
        # no ssl_client_hello_by_lua* with BoringSSL, and t/139 skips its
        # QUIC ssl_certificate_by_lua* tests there as well
        $SkipReason = "does not support BoringSSL";
    }
}

use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();

# ngx_get_connection() starts draining at 1024 / 16 = 64 free connections
worker_connections(1024);

repeat_each(1);

plan tests => repeat_each() * (blocks() * 6);

no_long_string();

add_block_preprocessor(sub {
    my $block = shift;

    # nginx hands its workers a bare environment, so the curl spawned below
    # would resolve against a default PATH and might not speak HTTP/3
    my $main_config = $block->main_config || '';
    $main_config .= <<'_EOC_';
env PATH;
_EOC_
    $block->set_value("main_config", $main_config);

    my $http_config = $block->http_config || '';
    $http_config .= <<'_EOC_';
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";

    init_by_lua_block {
        require "resty.core"
    }

    # takes the connections parked to run the worker short
    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_2;

        location / {
            return 200;
        }
    }
_EOC_
    $block->set_value("http_config", $http_config);

    my $config = $block->config || '';
    $config .= <<'_EOC_';
    location = /t {
        content_by_lua_block {
            -- each parked connection takes two slots, the cosocket and the
            -- accepted end: this leaves about 30 free, under the 64 at
            -- which draining starts but enough for the HTTP/3 request
            -- and its streams
            local socks = {}

            for i = 1, 495 do
                local sock = ngx.socket.tcp()

                local ok, err = sock:connect("127.0.0.1",
                                             $TEST_NGINX_RAND_PORT_2)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                -- no CRLF: nginx keeps waiting for the request line
                local bytes, err = sock:send("GET /")
                if not bytes then
                    ngx.say("failed to send: ", err)
                    return
                end

                socks[i] = sock

                -- let nginx accept the connection and read the partial
                -- line, so that no parked connection is still reusable
                -- when the QUIC handshake comes in
                ngx.sleep(0.001)
            end

            local proc, err = require("ngx.pipe").spawn({"curl", "--http3-only",
                                                         "-sk",
                                                         "--connect-timeout", "2",
                                                         "--max-time", "3",
                                                         "https://127.0.0.1:$TEST_NGINX_RAND_PORT_1/"})
            if not proc then
                ngx.say("failed to spawn curl: ", err)
                return
            end

            local out, err = proc:stdout_read_all()
            if not out then
                ngx.say("failed to read curl output: ", err)
                return
            end

            proc:wait()

            ngx.print(out)

            for _, sock in ipairs(socks) do
                sock:close()
            end
        }
    }
_EOC_
    $block->set_value("config", $config);
});

run_tests();

__DATA__

=== TEST 1: ssl_client_hello_by_lua on a QUIC connection with worker_connections running low
--- http_config
    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1 quic;
        server_name test.com;

        ssl_client_hello_by_lua_block {
            ngx.log(ngx.INFO, "ssl client hello by lua is running")
        }

        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        location / {
            return 200 "h3 ok\n";
        }
    }
--- request
GET /t
--- response_body
h3 ok
--- error_log
ssl client hello: connection reusable: 1
--- no_error_log
[alert]
[crit]
[error]
--- timeout: 10



=== TEST 2: ssl_certificate_by_lua on a QUIC connection with worker_connections running low
--- http_config
    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1 quic;
        server_name test.com;

        ssl_certificate_by_lua_block {
            ngx.log(ngx.INFO, "ssl certificate by lua is running")
        }

        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        location / {
            return 200 "h3 ok\n";
        }
    }
--- request
GET /t
--- response_body
h3 ok
--- error_log
ssl cert: connection reusable: 1
--- no_error_log
[alert]
[crit]
[error]
--- timeout: 10



=== TEST 3: both handlers: the client hello one hands the connection back reusable
--- http_config
    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1 quic;
        server_name test.com;

        ssl_client_hello_by_lua_block {
            ngx.log(ngx.INFO, "ssl client hello by lua is running")
        }

        ssl_certificate_by_lua_block {
            ngx.log(ngx.INFO, "ssl certificate by lua is running")
        }

        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        location / {
            return 200 "h3 ok\n";
        }
    }
--- request
GET /t
--- response_body
h3 ok
--- error_log
ssl cert: connection reusable: 1
--- no_error_log
[alert]
[crit]
[error]
--- timeout: 10



=== TEST 4: yielding ssl_client_hello_by_lua on a QUIC connection with worker_connections running low
--- http_config
    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1 quic;
        server_name test.com;

        ssl_client_hello_by_lua_block {
            ngx.sleep(0.001)
            ngx.log(ngx.INFO, "ssl client hello by lua is running")
        }

        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        location / {
            return 200 "h3 ok\n";
        }
    }
--- request
GET /t
--- response_body
h3 ok
--- error_log
ssl client hello: connection reusable: 1
--- no_error_log
[alert]
[crit]
[error]
--- timeout: 10



=== TEST 5: ssl_client_hello_by_lua that needs a connection after a yield
--- http_config
    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1 quic;
        server_name test.com;

        ssl_client_hello_by_lua_block {
            ngx.sleep(0.001)

            -- ngx_get_connection() again, while the handshake is parked;
            -- UDP, so that no accept() follows once the handler is done
            local sock = ngx.socket.udp()

            local ok, err = sock:setpeername("127.0.0.1",
                                             $TEST_NGINX_RAND_PORT_2)
            if not ok then
                ngx.log(ngx.ERR, "failed to set peer name: ", err)
                return
            end

            sock:close()
        }

        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        location / {
            return 200 "h3 ok\n";
        }
    }
--- request
GET /t
--- response_body
h3 ok
--- error_log
ssl client hello: connection reusable: 1
--- no_error_log
[alert]
[crit]
[error]
--- timeout: 10
