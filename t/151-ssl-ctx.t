# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use Digest::MD5 qw(md5_hex);

repeat_each(3);

# All these tests need to have new openssl
my $NginxBinary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $openssl_version = eval { `$NginxBinary -V 2>&1` };

if ($openssl_version =~ m/built with OpenSSL (0|1\.0\.(?:0|1[^\d]|2[a-d]).*)/) {
    plan(skip_all => "too old OpenSSL, need 1.0.2e, was $1");
} else {
    plan tests => repeat_each() * (blocks() + 2);
}

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

log_level 'debug';

no_long_string();

add_block_preprocessor(sub {
    my $block = shift;

    if (!defined $block->user_files) {
        $block->set_value("user_files", <<'_EOC_');
>>> defines.lua
local ffi = require "ffi"

ffi.cdef[[
    void *ngx_http_lua_ffi_ssl_ctx_init(const unsigned char *method,
        size_t method_len, char **err);

    void ngx_http_lua_ffi_ssl_ctx_free(void *cdata);

    int ngx_http_lua_ffi_ssl_ctx_set_priv_key(void *cdata_ctx,
        void *cdata_key, char **err);

    int ngx_http_lua_ffi_ssl_ctx_set_cert(void *cdata_ctx,
        void *cdata_cert, char **err);
]]
_EOC_
    }

    my $http_config = $block->http_config || '';
    $http_config .= <<'_EOC_';
lua_package_path "$prefix/html/?.lua;;";
_EOC_
    $block->set_value("http_config", $http_config);
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
            local method = "SSLv23_method"
            local errmsg = ffi.new("char *[1]")
            local ctx = ffi.C.ngx_http_lua_ffi_ssl_ctx_init(method, #method, errmsg)
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



=== TEST 2: ssl ctx init - disable ssl protocols method SSLv2 SSLv3
--- config
    location /t {
        content_by_lua_block {
            require "defines"
            local ffi = require "ffi"
            local method = "SSLv2_method"
            local errmsg = ffi.new("char *[1]")
            local ctx = ffi.C.ngx_http_lua_ffi_ssl_ctx_init(method, #method, errmsg)
            if ctx == nil then
                ngx.say(ffi.string(errmsg[0]))
            end
            local method = "SSLv3_method"
            local ctx = ffi.C.ngx_http_lua_ffi_ssl_ctx_init(method, #method, errmsg)
            if ctx == nil then
                ngx.say(ffi.string(errmsg[0]))
            end
        }
    }

--- request
GET /t
--- response_body
SSLv2 methods disabled
SSLv3 methods disabled



=== TEST 3: ssl ctx init - allow ssl protocols method TLSv1 TLSv1.1 TLSv1.2
--- config
    location /t {
        content_by_lua_block {
            require "defines"
            local ffi = require "ffi"
            local method = "TLSv1_method"
            local errmsg = ffi.new("char *[1]")
            local ctx = ffi.C.ngx_http_lua_ffi_ssl_ctx_init(method, #method, errmsg)
            if ctx == nil then
                ngx.say(ffi.string(errmsg[0]))
            else
                ngx.say("TLSv1_method ok")
            end
            method = "TLSv1_1_method"
            ctx = ffi.C.ngx_http_lua_ffi_ssl_ctx_init(method, #method, errmsg)
            if ctx == nil then
                ngx.say(ffi.string(errmsg[0]))
            else
                ngx.say("TLSv1_1_method ok")
            end
            method = "TLSv1_2_method"
            ctx = ffi.C.ngx_http_lua_ffi_ssl_ctx_init(method, #method, errmsg)
            if ctx == nil then
                ngx.say(ffi.string(errmsg[0]))
            else
                ngx.say("TLSv1_2_method ok")
            end
        }
    }

--- request
GET /t
--- response_body
TLSv1_method ok
TLSv1_1_method ok
TLSv1_2_method ok

