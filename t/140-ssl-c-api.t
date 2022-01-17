# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(3);

# All these tests need to have new openssl
my $NginxBinary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $openssl_version = eval { `$NginxBinary -V 2>&1` };

if ($openssl_version =~ m/built with OpenSSL (0|1\.0\.(?:0|1[^\d]|2[a-d]).*)/) {
    plan(skip_all => "too old OpenSSL, need 1.0.2e, was $1");

} else {
    plan tests => repeat_each() * (blocks() * 5 + 1);
}

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();

add_block_preprocessor(sub {
    my $block = shift;

    if (!defined $block->user_files) {
        $block->set_value("user_files", <<'_EOC_');
>>> defines.lua
local ffi = require "ffi"

ffi.cdef[[
    int ngx_http_lua_ffi_cert_pem_to_der(const unsigned char *pem,
        size_t pem_len, unsigned char *der, char **err);

    int ngx_http_lua_ffi_priv_key_pem_to_der(const unsigned char *pem,
        size_t pem_len, const unsigned char *passphrase,
        unsigned char *der, char **err);

    int ngx_http_lua_ffi_ssl_set_der_certificate(void *r,
        const char *data, size_t len, char **err);

    int ngx_http_lua_ffi_ssl_set_der_private_key(void *r,
        const char *data, size_t len, char **err);

    int ngx_http_lua_ffi_ssl_clear_certs(void *r, char **err);

    void *ngx_http_lua_ffi_parse_pem_cert(const unsigned char *pem,
        size_t pem_len, char **err);

    void *ngx_http_lua_ffi_parse_pem_priv_key(const unsigned char *pem,
        size_t pem_len, char **err);

    int ngx_http_lua_ffi_set_cert(void *r,
        void *cdata, char **err);

    int ngx_http_lua_ffi_set_priv_key(void *r,
        void *cdata, char **err);

    void *ngx_http_lua_ffi_get_req_ssl_pointer(void *r);

    void ngx_http_lua_ffi_free_cert(void *cdata);

    void ngx_http_lua_ffi_free_priv_key(void *cdata);

    int ngx_http_lua_ffi_ssl_verify_client(void *r, void *cdata,
        int depth, char **err);

]]
_EOC_
    }

    my $http_config = $block->http_config || '';
    $http_config .= <<'_EOC_';
lua_package_path "$prefix/html/?.lua;../lua-resty-core/lib/?.lua;;";
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: Raw SSL pointer
--- http_config
    lua_package_cpath "/opt/ssl/lib/?.so;;";
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate_by_lua_block {
            collectgarbage()

            local ffi = require "ffi"
            require "defines"

            local r = require "resty.core.base" .get_request()
            if not r then
                ngx.log(ngx.ERR, "no request found")
                return
            end

            local ssl = ffi.C.ngx_http_lua_ffi_get_req_ssl_pointer(r);
            if ssl == nil then
                ngx.log(ngx.ERR, "failed to retrieve SSL*")
                return
            end

            ffi.cdef[[
                const char *SSL_get_servername(const void *, const int);
            ]]
            local TLSEXT_NAMETYPE_host_name = 0
            local sni = ffi.string(ffi.C.SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name))
            ngx.log(ngx.INFO, "SNI is ", sni)
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
SNI is test.com

--- no_error_log
[error]
[alert]
