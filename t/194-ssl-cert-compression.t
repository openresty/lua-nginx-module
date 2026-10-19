# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 5);

log_level 'debug';

no_long_string();
#no_diff();

my $NginxBinary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $nginx_v = eval { `$NginxBinary -V 2>&1` } || '';

# SSL_compress_certs() arrived in OpenSSL 3.2.0. Against anything older, and
# against BoringSSL/LibreSSL, ngx_http_lua_ffi_ssl_compress_certs() refuses
# with the version error instead.
my ($ssl_major, $ssl_minor) = $nginx_v =~ m/built with OpenSSL (\d+)\.(\d+)/;

if (defined $ssl_major
    && $nginx_v !~ m/BoringSSL|LibreSSL/
    && ($ssl_major > 3 || ($ssl_major == 3 && $ssl_minor >= 2)))
{
    $ENV{TEST_NGINX_NO_CERT_COMP} = 0;

} else {
    $ENV{TEST_NGINX_NO_CERT_COMP} = 1;
}

# Whether a compression algorithm is actually built into the OpenSSL library
# is not visible from "nginx -V": OpenSSL needs to be configured with zlib,
# brotli or zstd, and most distribution builds are not. Set
# TEST_NGINX_CERT_COMP_ALGS=1 when yours is, and TEST 1 then insists on the
# compression succeeding rather than accepting either outcome.
$ENV{TEST_NGINX_CERT_COMP_ALGS} ||= 0;

# ssl_certificate_compression (nginx 1.29.1+) is what lets nginx put the
# compressed certificate on the wire. The FFI call itself does not depend on
# it, so on older nginx the tests simply run without the directive.
my ($nginx_major, $nginx_minor, $nginx_patch) =
    $nginx_v =~ m{nginx version: \S+?/(\d+)\.(\d+)\.(\d+)};

if (defined $nginx_major
    && ($nginx_major > 1
        || ($nginx_major == 1
            && ($nginx_minor > 29
                || ($nginx_minor == 29 && $nginx_patch >= 1)))))
{
    $ENV{TEST_NGINX_CERT_COMP_DIRECTIVE} = "ssl_certificate_compression on;";

} else {
    $ENV{TEST_NGINX_CERT_COMP_DIRECTIVE} = "";
}

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

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

    int ngx_http_lua_ffi_ssl_clear_certs(void *r, char **err);

    int ngx_http_lua_ffi_ssl_set_der_certificate(void *r,
        const char *data, size_t len, char **err);

    int ngx_http_lua_ffi_ssl_set_der_private_key(void *r,
        const char *data, size_t len, char **err);

    int ngx_http_lua_ffi_ssl_compress_certs(void *r, int alg, char **err);
]]

>>> helper.lua
local ffi = require "ffi"

require "defines"

local _M = {}

local function read_file(name)
    local f = assert(io.open(name, "rb"))
    local data = f:read("*all")
    f:close()
    return data
end

-- the ssl_certificate_by_lua* paradigm this module is about: drop whatever
-- nginx configured and install a certificate of our own
function _M.set_dynamic_cert(r, errmsg)
    local pem = read_file("t/cert/test.crt")
    local out = ffi.new("char [?]", #pem)

    local rc = ffi.C.ngx_http_lua_ffi_cert_pem_to_der(pem, #pem, out, errmsg)
    if rc < 1 then
        return nil, "failed to parse PEM cert: " .. ffi.string(errmsg[0])
    end

    local cert_der = ffi.string(out, rc)

    rc = ffi.C.ngx_http_lua_ffi_ssl_set_der_certificate(r, cert_der,
                                                        #cert_der, errmsg)
    if rc ~= 0 then
        return nil, "failed to set DER cert: " .. ffi.string(errmsg[0])
    end

    local key = read_file("t/cert/test.key")
    out = ffi.new("char [?]", #key)

    rc = ffi.C.ngx_http_lua_ffi_priv_key_pem_to_der(key, #key, nil, out,
                                                    errmsg)
    if rc < 1 then
        return nil, "failed to parse PEM priv key: " .. ffi.string(errmsg[0])
    end

    local key_der = ffi.string(out, rc)

    rc = ffi.C.ngx_http_lua_ffi_ssl_set_der_private_key(r, key_der,
                                                        #key_der, errmsg)
    if rc ~= 0 then
        return nil, "failed to set DER priv key: " .. ffi.string(errmsg[0])
    end

    return true
end

function _M.compress_certs(r, alg, errmsg)
    local rc = ffi.C.ngx_http_lua_ffi_ssl_compress_certs(r, alg, errmsg)
    if rc ~= 0 then
        ngx.log(ngx.WARN, "ssl cert compression: failed: ",
                ffi.string(errmsg[0]))
        return
    end

    ngx.log(ngx.WARN, "ssl cert compression: ok")
end

return _M
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

=== TEST 1: compress the certificate set by ssl_certificate_by_lua*
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate_by_lua_block {
            local ffi = require "ffi"
            local helper = require "helper"

            local errmsg = ffi.new("char *[1]")
            local r = require "resty.core.base" .get_request()

            local ok, err = helper.set_dynamic_cert(r, errmsg)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            helper.compress_certs(r, 0, errmsg)
        }

        ssl_certificate ../../cert/test2.crt;
        ssl_certificate_key ../../cert/test2.key;
        $TEST_NGINX_CERT_COMP_DIRECTIVE

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
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
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
$ENV{TEST_NGINX_NO_CERT_COMP}
    ? qr/ssl cert compression: failed: at least OpenSSL 3\.2\.0 required/
    : ($ENV{TEST_NGINX_CERT_COMP_ALGS}
       ? qr/ssl cert compression: ok/
       : qr/ssl cert compression: (?:ok|failed: SSL_get1_compressed_cert\(\) failed)/)
--- no_error_log
[error]
[alert]



=== TEST 2: unknown compression algorithm
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate_by_lua_block {
            local ffi = require "ffi"
            local helper = require "helper"

            local errmsg = ffi.new("char *[1]")
            local r = require "resty.core.base" .get_request()

            local ok, err = helper.set_dynamic_cert(r, errmsg)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            helper.compress_certs(r, 42, errmsg)
        }

        ssl_certificate ../../cert/test2.crt;
        ssl_certificate_key ../../cert/test2.key;
        $TEST_NGINX_CERT_COMP_DIRECTIVE

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
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
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
$ENV{TEST_NGINX_NO_CERT_COMP}
    ? qr/ssl cert compression: failed: at least OpenSSL 3\.2\.0 required/
    : qr/ssl cert compression: failed: unknown certificate compression algorithm/
--- no_error_log
[error]
[alert]



=== TEST 3: no certificate on the connection yet
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate_by_lua_block {
            local ffi = require "ffi"
            local helper = require "helper"

            local errmsg = ffi.new("char *[1]")
            local r = require "resty.core.base" .get_request()

            -- the connection carries no certificate at this point, so there
            -- is nothing for OpenSSL to pre-compress
            if ffi.C.ngx_http_lua_ffi_ssl_clear_certs(r, errmsg) ~= 0 then
                ngx.log(ngx.ERR, "failed to clear certs: ",
                        ffi.string(errmsg[0]))
                return
            end

            helper.compress_certs(r, 1, errmsg)

            local ok, err = helper.set_dynamic_cert(r, errmsg)
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end
        }

        ssl_certificate ../../cert/test2.crt;
        ssl_certificate_key ../../cert/test2.key;
        $TEST_NGINX_CERT_COMP_DIRECTIVE

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
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
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
$ENV{TEST_NGINX_NO_CERT_COMP}
    ? qr/ssl cert compression: failed: at least OpenSSL 3\.2\.0 required/
    : qr/ssl cert compression: failed: no certificate set on this connection/
--- no_error_log
[error]
[alert]
