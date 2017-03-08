# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use Digest::MD5 qw(md5_hex);

repeat_each(3);

plan tests => repeat_each() * (blocks());

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

log_level 'debug';

no_long_string();

run_tests();

__DATA__

=== TEST 1: ssl ctx init and free
--- log_level: debug
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";
--- config
    location /t {
        content_by_lua_block {
            local ssl = require "ngx.ssl"
            local ssl_ctx, err = ssl.create_ctx({})
            ssl_ctx = nil
            collectgarbage("collect")
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
