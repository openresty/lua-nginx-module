# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;

log_level('debug');
repeat_each(1);

plan tests => repeat_each() * (blocks() * 3 + 2);

no_long_string();

our $BalancerHelper = <<'_EOC_';
    init_by_lua_block {
        local ffi = require "ffi"

        -- declares the symbol, with whatever prototype the lua-resty-core
        -- version in use has
        require "ngx.balancer"

        -- call the C function through an explicit prototype, so that the
        -- tests do not depend on the FFI declaration of the lua-resty-core
        -- version in use
        local enable_keepalive = ffi.cast(
            "int (*)(void *r, unsigned long timeout, unsigned int max_requests,"
            .. " unsigned int pool_size, char **err)",
            ffi.C.ngx_http_lua_ffi_balancer_enable_keepalive)

        local errmsg = ffi.new("char *[1]")

        function enable_keepalive_pool(pool_size)
            local r = require("resty.core.base").get_request()
            local rc = enable_keepalive(r, 60000, 100, pool_size, errmsg)
            if rc ~= 0 then
                return nil, ffi.string(errmsg[0])
            end

            return true
        end
    }
_EOC_

our $Backend = <<'_EOC_';
    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1;

        keepalive_requests 1000;

        location = /conn {
            content_by_lua_block {
                ngx.print(ngx.var.connection)
            }
        }
    }
_EOC_

our $ProxyLoc = <<'_EOC_';
    location = /proxy {
        internal;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_pass http://backend/conn;
    }
_EOC_

add_block_preprocessor(sub {
    my $block = shift;

    if (defined $block->http_upstream) {
        $block->set_value("http_config", $BalancerHelper
                          . $block->http_upstream . $Backend);
    }

    if (defined $block->config) {
        $block->set_value("config", $block->config . $ProxyLoc);
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!defined $block->no_error_log) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: pool_size caps the idle connections of a pool
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1,
                                      "one"))
            assert(enable_keepalive_pool(1))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local function conns(n)
                local reqs = {}
                for i = 1, n do
                    reqs[i] = { "/proxy" }
                end

                local ids = {}
                for i, res in ipairs({ ngx.location.capture_multi(reqs) }) do
                    assert(res.status == 200, "bad status " .. res.status)
                    ids[i] = res.body
                end

                return ids
            end

            -- 3 concurrent requests open 3 connections, but only one of
            -- them may stay idle in the pool once they are all released
            local first = {}
            for _, id in ipairs(conns(3)) do
                first[id] = true
            end

            local reused = 0
            for _, id in ipairs(conns(2)) do
                if first[id] then
                    reused = reused + 1
                end
            end

            ngx.say("reused: ", reused)
        }
    }
--- response_body
reused: 1
--- error_log
lua balancer: keepalive pool full, evicting connection



=== TEST 2: a full pool does not evict the idle connections of other pools
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;
        balancer_keepalive 2;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1,
                                      ngx.var.arg_pool))
            assert(enable_keepalive_pool(1))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local b1 = ngx.location.capture("/proxy", { args = "pool=b" }).body

            -- two concurrent connections for pool "a": the second one to be
            -- released must evict the first one, not the idle one of "b"
            ngx.location.capture_multi({
                { "/proxy", { args = "pool=a" } },
                { "/proxy", { args = "pool=a" } },
            })

            local b2 = ngx.location.capture("/proxy", { args = "pool=b" }).body

            ngx.say("pool b reused: ", b1 == b2)
        }
    }
--- response_body
pool b reused: true



=== TEST 3: no pool_size: a busy pool evicts idle connections of other pools
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;
        balancer_keepalive 2;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1,
                                      ngx.var.arg_pool))
            assert(enable_keepalive_pool(0))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local b1 = ngx.location.capture("/proxy", { args = "pool=b" }).body

            ngx.location.capture_multi({
                { "/proxy", { args = "pool=a" } },
                { "/proxy", { args = "pool=a" } },
            })

            local b2 = ngx.location.capture("/proxy", { args = "pool=b" }).body

            ngx.say("pool b reused: ", b1 == b2)
        }
    }
--- response_body
pool b reused: false



=== TEST 4: error paths still report through the err argument
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;

        balancer_by_lua_block {
            -- no current peer set yet
            local ok, err = enable_keepalive_pool(1)
            ngx.log(ngx.WARN, "enable keepalive: ", ok, " ", err)

            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
        }
    }
--- response_body
status: 200
--- error_log
enable keepalive: nil no current peer set
