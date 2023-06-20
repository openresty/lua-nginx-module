# vim:set ft= ts=4 sw=4 et:
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;
$ENV{TEST_NGINX_STREAM_REDIS_PORT} ||= 12345;

my $MainConfig = qq{
    stream {
        server {
            listen unix:$ENV{TEST_NGINX_HTML_DIR}/nginx.sock;
            listen unix:$ENV{TEST_NGINX_HTML_DIR}/nginx-ssl.sock ssl;
            listen 127.0.0.1:$ENV{TEST_NGINX_STREAM_REDIS_PORT} ssl;

            ssl_certificate ../../cert/redis.crt;
            ssl_certificate_key ../../cert/redis.key;
            ssl_trusted_certificate ../../cert/redis_ca.crt;

            proxy_pass 127.0.0.1:$ENV{TEST_NGINX_REDIS_PORT};
        }
    }
};

my $pwd = cwd();
my $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
};

add_block_preprocessor(sub {
    my $block = shift;

    if (!defined $block->main_config) {
        $block->set_value("main_config", $MainConfig);
    }

    if (!defined $block->http_config) {
        $block->set_value("http_config", $HttpConfig);
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: ssl connection (without certificate and certificate_key)
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(100)

            local ok, err = red:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock", {
                ssl = true
            })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("ok")
        }
    }
--- request
    GET /t
--- response_body
failed to connect: failed to do ssl handshake: handshake failed

=== TEST 2: ssl connection (with certificate and certificate_key)
--- config
    lua_ssl_certificate ../../cert/redis.crt;
    lua_ssl_certificate_key ../../cert/redis.key;

    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(100)

            local ok, err = red:connect("unix:$TEST_NGINX_HTML_DIR/nginx-ssl.sock", {
                ssl = true
            })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("ok")
        }
    }
--- request
    GET /t
--- response_body
ok

=== TEST 3: ssl connection two-way authentication (with certificate and certificate_key and trusted_certificate)
--- config
    lua_ssl_certificate ../../cert/redis.crt;
    lua_ssl_certificate_key ../../cert/redis.key;
    lua_ssl_trusted_certificate ../../cert/redis_ca.crt;

    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(100)

            local ok, err = red:connect("unix:$TEST_NGINX_HTML_DIR/nginx-ssl.sock", {
                ssl = true,
                ssl_verify = true
            })
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("ok")
        }
    }
--- request
    GET /t
--- response_body
ok

