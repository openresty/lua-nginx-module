use Test::Nginx::Socket 'no_plan';

$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

run_tests();

__DATA__

=== TEST 1: ssl connection (without certificate and certificate_key)
--- config
    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(100)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, {
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

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, {
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

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, {
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

=== TEST 4: ssl connection with certificate_key (without certificate)
--- config
    lua_ssl_certificate_key ../../cert/redis.key;

    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()

            red:set_timeout(100)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, {
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

=== TEST 5: timer ssl connection (without certificate and certificate_key)
--- config

    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()
            local begin = ngx.now()

            local function f()
                local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, {
                ssl = true
            })
                red:set("cat", "an animal")
            end
            local ok, err = ngx.timer.at(0.05, f)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, {
                ssl = true
            })

            local res, err = red:get("cat")
            if err then
                ngx.say("failed to get cat: ", err)
                return
            end

            if not res then
                ngx.say("cat not found.")
                return
            end

            ngx.say("cat: ", res)
        }
    }
--- request
    GET /t
--- response_body
failed to get cat: closed

=== TEST 6: timer ssl connection (with certificate and certificate_key)
--- config
    lua_ssl_certificate ../../cert/redis.crt;
    lua_ssl_certificate_key ../../cert/redis.key;

    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()
            local begin = ngx.now()

            local function f()
                local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, {
                ssl = true
            })
                red:set("cat", "an animal")
            end
            local ok, err = ngx.timer.at(0.05, f)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, {
                ssl = true
            })

            local res, err = red:get("cat")
            if err then
                ngx.say("failed to get cat: ", err)
                return
            end

            if not res then
                ngx.say("cat not found.")
                return
            end

            ngx.say("cat: ", res)
        }
    }
--- request
    GET /t
--- response_body
cat: an animal

=== TEST 7: timer ssl connection two-way authentication (with certificate and certificate_key and trusted_certificate)
--- config
    lua_ssl_certificate ../../cert/redis.crt;
    lua_ssl_certificate_key ../../cert/redis.key;
    lua_ssl_trusted_certificate ../../cert/redis_ca.crt;

    location /t {
        content_by_lua_block {
            local redis = require "resty.redis"
            local red = redis:new()
            local begin = ngx.now()

            local function f()
                local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, {
                ssl = true,
                ssl_verify = true
            })
                red:set("cat", "an animal")
            end
            local ok, err = ngx.timer.at(0.05, f)

            local ok, err = red:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT, {
                ssl = true,
                ssl_verify = true
            })

            local res, err = red:get("cat")
            if err then
                ngx.say("failed to get cat: ", err)
                return
            end

            if not res then
                ngx.say("cat not found.")
                return
            end

            ngx.say("cat: ", res)
        }
    }
--- request
    GET /t
--- response_body
cat: an animal