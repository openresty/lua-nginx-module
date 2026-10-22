# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;

log_level('debug');
repeat_each(1);

plan tests => repeat_each() * (blocks() * 3 + 13);

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

        -- timeout is in milliseconds, as the C function expects it
        function enable_keepalive_pool(pool_size, timeout, max_requests)
            local r = require("resty.core.base").get_request()
            local rc = enable_keepalive(r, timeout or 60000,
                                        max_requests or 100, pool_size,
                                        errmsg)
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
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_2;

        keepalive_requests 1000;

        location = /conn {
            content_by_lua_block {
                -- the peer address shows which local address was bound
                ngx.print(ngx.var.connection, "|", ngx.var.remote_addr)
            }
        }

        location = /conn_short {
            keepalive_timeout 100ms;

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

    location = /proxy_short {
        internal;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_pass http://backend/conn_short;
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



=== TEST 5: many pools churning through a small cache
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;
        balancer_keepalive 4;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1,
                                      ngx.var.arg_pool))
            assert(enable_keepalive_pool(2))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local bad = 0

            for round = 1, 3 do
                for p = 1, 8 do
                    local args = "pool=p" .. p
                    local res = { ngx.location.capture_multi({
                        { "/proxy", { args = args } },
                        { "/proxy", { args = args } },
                        { "/proxy", { args = args } },
                    }) }

                    res[4] = ngx.location.capture("/proxy", { args = args })

                    for _, r in ipairs(res) do
                        if r.status ~= 200 then
                            bad = bad + 1
                        end
                    end
                end
            end

            ngx.say("failed requests: ", bad)
        }
    }
--- response_body
failed requests: 0
--- no_error_log
[error]
[alert]
[crit]



=== TEST 6: an idle connection closed by the peer leaves its pool
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1,
                                      "one"))
            assert(enable_keepalive_pool(2))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local r1 = ngx.location.capture("/proxy_short")

            -- the backend closes the idle connection after 100ms
            ngx.sleep(0.3)

            local r2 = ngx.location.capture("/proxy_short")
            local r3 = ngx.location.capture("/proxy_short")

            ngx.say("status: ", r1.status, " ", r2.status, " ", r3.status)
            ngx.say("closed one reused: ", r1.body == r2.body)
            ngx.say("new one reused: ", r2.body == r3.body)
        }
    }
--- response_body
status: 200 200 200
closed one reused: false
new one reused: true
--- error_log
lua balancer: keepalive closing connection
--- no_error_log
[error]
[alert]



=== TEST 7: a pool holding exactly pool_size connections evicts nothing
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1,
                                      "one"))
            assert(enable_keepalive_pool(3))
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

            local first = {}
            for _, id in ipairs(conns(3)) do
                first[id] = true
            end

            local reused = 0
            for _, id in ipairs(conns(3)) do
                if first[id] then
                    reused = reused + 1
                end
            end

            ngx.say("reused: ", reused)
        }
    }
--- response_body
reused: 3
--- no_error_log
[error]
lua balancer: keepalive pool full



=== TEST 8: pool_size larger than balancer_keepalive never raises the total
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;
        balancer_keepalive 2;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1,
                                      "one"))
            assert(enable_keepalive_pool(5))
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

            local first = {}
            for _, id in ipairs(conns(3)) do
                first[id] = true
            end

            local reused = 0
            for _, id in ipairs(conns(3)) do
                if first[id] then
                    reused = reused + 1
                end
            end

            ngx.say("reused: ", reused)
        }
    }
--- response_body
reused: 2
--- no_error_log
[error]
lua balancer: keepalive pool full



=== TEST 9: the host and the peer address both split pools
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", tonumber(ngx.var.arg_port),
                                      ngx.var.arg_host))
            assert(enable_keepalive_pool(1))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local keys = {
                "port=$TEST_NGINX_RAND_PORT_1&host=a",
                "port=$TEST_NGINX_RAND_PORT_1&host=b",
                "port=$TEST_NGINX_RAND_PORT_2&host=a",
            }

            -- concurrent first: every key opens its own connection
            local reqs = {}
            for i, args in ipairs(keys) do
                reqs[i] = { "/proxy", { args = args } }
            end

            local first = {}
            for i, res in ipairs({ ngx.location.capture_multi(reqs) }) do
                assert(res.status == 200, "bad status " .. res.status)
                first[i] = res.body
            end

            -- with pool_size 1, two keys sharing a pool would keep only one
            -- of their two connections, so one key would get the other's
            local second = {}
            for i, args in ipairs(keys) do
                local res = ngx.location.capture("/proxy", { args = args })
                assert(res.status == 200, "bad status " .. res.status)
                second[i] = res.body
            end

            for i = 1, #keys do
                ngx.say("key ", i, " reused its own: ", first[i] == second[i])
            end
        }
    }
--- response_body
key 1 reused its own: true
key 2 reused its own: true
key 3 reused its own: true
--- no_error_log
[error]



=== TEST 10: the bound local address splits pools
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1,
                                      "one"))

            if ngx.var.arg_local then
                assert(b.bind_to_local_addr(ngx.var.arg_local))
            end

            assert(enable_keepalive_pool(1))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local function get(args)
                local res = ngx.location.capture("/proxy", { args = args })
                assert(res.status == 200, "bad status " .. res.status)
                return res.body
            end

            local a1 = get("")
            local l1 = get("local=127.0.0.2")
            local a2 = get("")
            local l2 = get("local=127.0.0.2")

            ngx.say("unbound reused its own: ", a1 == a2)
            ngx.say("bound reused its own: ", l1 == l2)
            ngx.say("bound from: ", l1:match("|(.+)$"))
        }
    }
--- response_body
unbound reused its own: true
bound reused its own: true
bound from: 127.0.0.2
--- no_error_log
[error]



=== TEST 11: an idle connection expiring on its idle timeout leaves its pool
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1,
                                      "one"))
            -- 100ms idle timeout, the backend keeps the connection open
            assert(enable_keepalive_pool(2, 100))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local r1 = ngx.location.capture("/proxy")

            ngx.sleep(0.3)

            local r2 = ngx.location.capture("/proxy")
            local r3 = ngx.location.capture("/proxy")

            ngx.say("status: ", r1.status, " ", r2.status, " ", r3.status)
            ngx.say("expired one reused: ", r1.body == r2.body)
            ngx.say("new one reused: ", r2.body == r3.body)
        }
    }
--- response_body
status: 200 200 200
expired one reused: false
new one reused: true
--- error_log
lua balancer: keepalive closing connection
--- no_error_log
[error]
[alert]



=== TEST 12: a connection reaching max_requests is not cached
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;

        balancer_by_lua_block {
            local b = require "ngx.balancer"
            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1,
                                      "one"))
            assert(enable_keepalive_pool(2, nil, 2))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local r1 = ngx.location.capture("/proxy")
            local r2 = ngx.location.capture("/proxy")
            local r3 = ngx.location.capture("/proxy")
            local r4 = ngx.location.capture("/proxy")

            ngx.say("status: ", r1.status, " ", r2.status, " ", r3.status,
                    " ", r4.status)
            ngx.say("2nd reused the 1st: ", r1.body == r2.body)
            ngx.say("3rd reused the 2nd: ", r2.body == r3.body)
            ngx.say("4th reused the 3rd: ", r3.body == r4.body)
        }
    }
--- response_body
status: 200 200 200 200
2nd reused the 1st: true
3rd reused the 2nd: false
4th reused the 3rd: true
--- no_error_log
[error]
[alert]



=== TEST 13: a failed try is not cached, the retry's connection is
--- http_upstream
    upstream backend {
        server 0.0.0.1;
        keepalive 0;

        balancer_by_lua_block {
            local b = require "ngx.balancer"

            if not ngx.ctx.tried then
                ngx.ctx.tried = true
                assert(b.set_more_tries(1))
                -- nothing listens on this port
                assert(b.set_current_peer("127.0.0.1",
                                          $TEST_NGINX_RAND_PORT_3, "one"))

            else
                assert(b.set_current_peer("127.0.0.1",
                                          $TEST_NGINX_RAND_PORT_1, "one"))
            end

            assert(enable_keepalive_pool(1))
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            local r1 = ngx.location.capture("/proxy")
            local r2 = ngx.location.capture("/proxy")

            ngx.say("status: ", r1.status, " ", r2.status)
            ngx.say("retry connection reused: ", r1.body == r2.body)
        }
    }
--- response_body
status: 200 200
retry connection reused: true
--- error_log
Connection refused
--- no_error_log
[alert]
[crit]
