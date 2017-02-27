# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use Digest::MD5 qw(md5_hex);

repeat_each(3);

plan tests => repeat_each() * (blocks());

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
    void *ngx_http_lua_ffi_ssl_ctx_init(unsigned int protocols, char **err);

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
