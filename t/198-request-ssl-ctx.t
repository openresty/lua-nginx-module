# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);
plan tests => repeat_each() * blocks() * 3;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
no_long_string();
log_level 'info';

add_block_preprocessor(sub {
    my $block = shift;
    my $config = $block->http_config || '';
    $config .= <<'_EOC_';
lua_package_path "$prefix/html/?.lua;../lua-resty-core/lib/?.lua;;";
_EOC_
    $block->set_value("http_config", $config);
    $block->set_value("user_files", <<'_EOC_');
>>> ssl_ctx.lua
local ffi = require "ffi"
local get_request = require("resty.core.base").get_request

ffi.cdef[[
    typedef struct ssl_ctx_st SSL_CTX;
    SSL_CTX *ngx_http_lua_ffi_get_req_ssl_ctx(void *r, const char **err);
    SSL_CTX *SSL_get_SSL_CTX(const void *ssl);
    int SSL_CTX_get_verify_depth(const SSL_CTX *ctx);
]]

local C = ffi.C
local _M = {}

function _M.get(r)
    local err = ffi.new("const char *[1]")
    local ctx = C.ngx_http_lua_ffi_get_req_ssl_ctx(r, err)
    return ctx, err[0] ~= nil and ffi.string(err[0]) or nil
end

function _M.depths()
    local ctx, err = _M.get(get_request())
    assert(ctx ~= nil, err)
    assert(ffi.istype("SSL_CTX *", ctx))
    assert(ctx == _M.get(get_request()))

    local ssl = assert(require("ngx.ssl").get_req_ssl_pointer())
    return C.SSL_CTX_get_verify_depth(ctx),
           C.SSL_CTX_get_verify_depth(C.SSL_get_SSL_CTX(ssl))
end

return _M
_EOC_
});

run_tests();

__DATA__

=== TEST 1: NULL request returns an error
--- config
    location /t {
        content_by_lua_block {
            local ctx, err = require("ssl_ctx").get(nil)
            ngx.say(ctx == nil, ": ", err)
        }
    }
--- request
GET /t
--- response_body
true: bad request
--- no_error_log
[error]



=== TEST 2: plain connection returns an error
--- no_http3
--- config
    location /t {
        content_by_lua_block {
            local r = require("resty.core.base").get_request()
            local ctx, err = require("ssl_ctx").get(r)
            ngx.say(ctx == nil, ": ", err)
        }
    }
--- request
GET /t
--- response_body
true: bad request
--- no_error_log
[error]



=== TEST 3: TLS context is readable during certificate and content phases
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/ctx-3.sock ssl;
        server_name default.test;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        ssl_verify_depth 3;

        ssl_certificate_by_lua_block {
            local session_depth, active_depth = require("ssl_ctx").depths()
            assert(session_depth == 3)
            assert(active_depth == 3)
        }

        location / {
            content_by_lua_block {
                local session_depth, active_depth = require("ssl_ctx").depths()
                ngx.say(session_depth, ":", active_depth)
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            assert(sock:connect("unix:$TEST_NGINX_HTML_DIR/ctx-3.sock"))
            assert(sock:sslhandshake(nil, "default.test", false))
            assert(sock:send("GET / HTTP/1.0\r\nHost: default.test\r\n\r\n"))
            local data = assert(sock:receive("*a"))
            local _, header_end = data:find("\r\n\r\n", 1, true)
            assert(header_end)
            ngx.print(data:sub(header_end + 1))
            assert(sock:close())
        }
    }
--- request
GET /t
--- response_body
3:3
--- no_error_log
[error]



=== TEST 4: SNI preserves the original session context
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/ctx-4.sock ssl;
        server_name default.test;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        ssl_verify_depth 3;

        ssl_certificate_by_lua_block {
            local session_depth, active_depth = require("ssl_ctx").depths()
            assert(session_depth == 3)
            assert(active_depth == 3)
        }

        location / {
            content_by_lua_block {
                local session_depth, active_depth = require("ssl_ctx").depths()
                ngx.say(session_depth, ":", active_depth)
            }
        }
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/ctx-4.sock ssl;
        server_name selected.test;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        ssl_verify_depth 7;

        ssl_certificate_by_lua_block {
            local session_depth, active_depth = require("ssl_ctx").depths()
            assert(session_depth == 3)
            assert(active_depth == 7)
        }

        location / {
            content_by_lua_block {
                local session_depth, active_depth = require("ssl_ctx").depths()
                ngx.say(session_depth, ":", active_depth)
            }
        }
    }
--- config
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            assert(sock:connect("unix:$TEST_NGINX_HTML_DIR/ctx-4.sock"))
            assert(sock:sslhandshake(nil, "selected.test", false))
            assert(sock:send("GET / HTTP/1.0\r\nHost: selected.test\r\n\r\n"))
            local data = assert(sock:receive("*a"))
            local _, header_end = data:find("\r\n\r\n", 1, true)
            assert(header_end)
            ngx.print(data:sub(header_end + 1))
            assert(sock:close())
        }
    }
--- request
GET /t
--- response_body
3:7
--- no_error_log
[error]
