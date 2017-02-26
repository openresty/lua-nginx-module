# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);
use Digest::MD5 qw(md5_hex);

repeat_each(3);

plan tests => repeat_each() * (blocks() + 2);

our $CWD = cwd();
$ENV{TEST_NGINX_LUA_PACKAGE_PATH} = "$::CWD/lib/?.lua;;";
$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
our $TEST_NGINX_LUA_PACKAGE_PATH = $ENV{TEST_NGINX_LUA_PACKAGE_PATH};
our $TEST_NGINX_HTML_DIR = $ENV{TEST_NGINX_HTML_DIR};

log_level 'debug';

no_long_string();

sub read_file {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $clientKey = read_file("t/cert/ca-client-server/client.key");
our $clientUnsecureKey = read_file("t/cert/ca-client-server/client.unsecure.key");
our $clientCrt = read_file("t/cert/ca-client-server/client.crt");
our $clientCrtMd5 = md5_hex($clientCrt);
our $serverKey = read_file("t/cert/ca-client-server/server.key");
our $serverUnsecureKey = read_file("t/cert/ca-client-server/server.unsecure.key");
our $serverCrt = read_file("t/cert/ca-client-server/server.crt");
our $caKey = read_file("t/cert/ca-client-server/ca.key");
our $caCrt = read_file("t/cert/ca-client-server/ca.crt");
our $http_config = <<_EOS_;
lua_package_path "\$prefix/html/?.lua;$TEST_NGINX_LUA_PACKAGE_PATH/?.lua;;../lua-resty-lrucache/lib/?.lua;";

init_by_lua_block {
    local ffi = require "ffi"

    local C = ffi.C
    local ffi_str = ffi.string
    local getfenv = getfenv
    local error = error
    local errmsg = ffi.new("char *[1]")
    if not pcall(ffi.typeof, "ngx_http_request_t") then
      ffi.cdef[[
        struct ngx_http_request_s;
        typedef struct ngx_http_request_s  ngx_http_request_t;
      ]]
    end

    ffi.cdef[[
        int
        ngx_http_lua_ffi_socket_tcp_setsslctx(ngx_http_request_t *r,
            void *u, void *cdata_ctx, char **err);
    ]]

    local function check_tcp(tcp)
        if not tcp or type(tcp) ~= "table" then
            return error("bad tcp argument")
        end

        tcp = tcp[1]
        if type(tcp) ~= "userdata" then
            return error("bad tcp argument")
        end

        return tcp
    end

    local function setsslctx(tcp, ssl_ctx)
        tcp = check_tcp(tcp)

        local r = getfenv(0).__ngx_req
        if not r then
            return error("no request found")
        end

        local rc = C.ngx_http_lua_ffi_socket_tcp_setsslctx(r, tcp, ssl_ctx, errmsg)
        if rc ~= 0 then
            return false, ffi_str(errmsg[0])
        end

        return true
    end


    local mt = getfenv(0).__ngx_socket_tcp_mt
    if mt then
        mt = mt.__index
        if mt then
            mt.setsslctx = setsslctx
        end
    end

    function read_file(file)
        local f = io.open(file, "rb")
        local content = f:read("*all")
        f:close()
        return content
    end

    function get_response_body(response)
        for k, v in ipairs(response) do
            if #v == 0 then
                return table.concat(response, "\\r\\n", k + 1)
            end
        end

        return nil, "CRLF not found"
    end

    function https_get(host, port, path, ssl_ctx)
        local sock = ngx.socket.tcp()

        local ok, err = sock:connect(host, port)
        if not ok then
            return nil, err
        end

        local ok, err = sock:setsslctx(ssl_ctx)
        if not ok then
            return nil, err
        end

        local sess, err = sock:sslhandshake()
        if not sess then
            return nil, err
        end

        local req = "GET " .. path .. " HTTP/1.0\\r\\nHost: server\\r\\nConnection: close\\r\\n\\r\\n"
        local bytes, err = sock:send(req)
        if not bytes then
            return nil, err
        end

        local response = {}
        while true do
            local line, err, partial = sock:receive()
            if not line then
                if not partial then
                    response[#response+1] = partial
                end
                break
            end

            response[#response+1] = line
        end

        sock:close()

        return response
    end
}

server {
    listen 1983 ssl;
    server_name   server;
    ssl_certificate ../html/server.crt;
    ssl_certificate_key ../html/server.unsecure.key;

    ssl on;
    ssl_client_certificate ../html/ca.crt;
    ssl_verify_client on;

    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;

    ssl_prefer_server_ciphers  on;

    server_tokens off;
    more_clear_headers Date;
    default_type 'text/plain';

    location / {
        content_by_lua_block {
            ngx.say("foo")
        }
    }

    location /protocol {
        content_by_lua_block {ngx.say(ngx.var.ssl_protocol)}
    }

    location /cert {
        content_by_lua_block {
            ngx.say(ngx.md5(ngx.var.ssl_client_raw_cert))
        }
    }
}
_EOS_
our $user_files = <<_EOS_;
>>> client.key
$clientKey
>>> client.unsecure.key
$clientUnsecureKey
>>> client.crt
$clientCrt
>>> server.key
$serverKey
>>> server.unsecure.key
$serverUnsecureKey
>>> server.crt
$serverCrt
>>> ca.key
$caKey
>>> ca.crt
$caCrt
>>> wrong.crt
OpenResty
>>> wrong.key
OpenResty
>>> defines.lua
local ffi = require "ffi"

ffi.cdef[[
    void *ngx_http_lua_ffi_ssl_ctx_init(unsigned int protocols, char **err);

    void ngx_http_lua_ffi_ssl_ctx_free(void *cdata);

    int ngx_http_lua_ffi_ssl_ctx_set_priv_key(void *cdata_ctx,
        void *cdata_key, char **err);

    int ngx_http_lua_ffi_ssl_ctx_set_cert(void *cdata_ctx,
        void *cdata_cert, char **err);

    void *ngx_http_lua_ffi_parse_pem_cert(const unsigned char *pem,
        size_t pem_len, char **err);

    void *ngx_http_lua_ffi_parse_pem_priv_key(const unsigned char *pem,
        size_t pem_len, char **err);
]]
_EOS_

add_block_preprocessor(sub {
    my $block = shift;

    $block->set_value("http_config", $http_config);
    $block->set_value("user_files", $user_files);
});

run_tests();

__DATA__

=== TEST 1: ssl ctx init and free
--- log_level: debug
--- config
    location /t {
        content_by_lua_block {
            require "defines"
            local ffi = require "ffi"
            local errmsg = ffi.new("char *[1]")
            local ctx = ffi.C.ngx_http_lua_ffi_ssl_ctx_init(0, errmsg)
            if ctx == nil then
                ngx.say(ffi.string(errmsg[0]))
                return
            end

            ffi.C.ngx_http_lua_ffi_ssl_ctx_free(ctx)
        }
    }
--- request
GET /t
--- ignore_response
--- grep_error_log eval: qr/lua ssl ctx (?:init|free): [0-9A-F]+:\d+/
--- grep_error_log_out eval
qr/^lua ssl ctx init: ([0-9A-F]+):1
lua ssl ctx free: ([0-9A-F]+):1
$/



=== TEST 2: ssl ctx - specify ssl protocols method TLSv1 TLSv1.1 TLSv1.2
--- config
    location /t {
        content_by_lua_block {
            require "defines"
            local ffi = require "ffi"
            function test_ssl_protocol(protocols)
                local errmsg = ffi.new("char *[1]")
                local cert_data = read_file("$TEST_NGINX_HTML_DIR/client.crt")
                local cert = ffi.C.ngx_http_lua_ffi_parse_pem_cert(cert_data, #cert_data, errmsg)
                local pkey_data = read_file("$TEST_NGINX_HTML_DIR/client.unsecure.key")
                local priv_key = ffi.C.ngx_http_lua_ffi_parse_pem_priv_key(pkey_data, #pkey_data, errmsg)

                local ssl_ctx = ffi.C.ngx_http_lua_ffi_ssl_ctx_init(protocols, errmsg)
                if ssl_ctx == nil then
                    ngx.say(ffi.string(errmsg[0]))
                    return
                end

                local rc = ffi.C.ngx_http_lua_ffi_ssl_ctx_set_priv_key(ssl_ctx, priv_key, errmsg)
                if rc ~= 0 then
                    ngx.say(ffi.string(errmsg[0]))
                    return
                end

                local rc = ffi.C.ngx_http_lua_ffi_ssl_ctx_set_cert(ssl_ctx, cert, errmsg)
                if rc ~= 0 then
                    ngx.say(ffi.string(errmsg[0]))
                    return
                end

                local response, err = https_get('127.0.0.1', 1983, '/protocol', ssl_ctx)

                if not response then
                    return err
                end

                local body, err = get_response_body(response)
                if not body then
                    return err
                end
                return body
            end

            local bit = require "bit"
            local bor = bit.bor
            --[=[
              _M.PROTOCOL_SSLv2 = 0x0002
              _M.PROTOCOL_SSLv3 = 0x0004
              _M.PROTOCOL_TLSv1 = 0x0008
              _M.PROTOCOL_TLSv1_1 = 0x0010
              _M.PROTOCOL_TLSv1_2 = 0x0020
            ]=]

            ngx.say(test_ssl_protocol(0x0008))
            ngx.say(test_ssl_protocol(0x0010))
            ngx.say(test_ssl_protocol(0x0020))
            ngx.say(test_ssl_protocol(bor(0x0002, 0x0020)))
        }
    }

--- request
GET /t
--- response_body
TLSv1
TLSv1.1
TLSv1.2
TLSv1.2



=== TEST 3: ssl ctx - dismatch priv_key and cert
--- config
    location /t {
        content_by_lua_block {
            require "defines"
            local ffi = require "ffi"
            local errmsg = ffi.new("char *[1]")
            local cert_data = read_file("$TEST_NGINX_HTML_DIR/server.crt")
            local cert = ffi.C.ngx_http_lua_ffi_parse_pem_cert(cert_data, #cert_data, errmsg)
            local pkey_data = read_file("$TEST_NGINX_HTML_DIR/client.unsecure.key")
            local priv_key = ffi.C.ngx_http_lua_ffi_parse_pem_priv_key(pkey_data, #pkey_data, errmsg)

            local ssl_ctx = ffi.C.ngx_http_lua_ffi_ssl_ctx_init(0, errmsg)
            if ssl_ctx == nil then
                ngx.say(ffi.string(errmsg[0]))
                return
            end

            local rc = ffi.C.ngx_http_lua_ffi_ssl_ctx_set_cert(ssl_ctx, cert, errmsg)
            if rc ~= 0 then
                ngx.say(ffi.string(errmsg[0]))
                return
            end

            local rc = ffi.C.ngx_http_lua_ffi_ssl_ctx_set_priv_key(ssl_ctx, priv_key, errmsg)
            if rc ~= 0 then
                ngx.say(ffi.string(errmsg[0]))
                return
            end
        }
    }

--- request
GET /t
--- response_body
SSL_CTX_use_PrivateKey() failed
