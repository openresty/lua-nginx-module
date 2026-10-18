# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

log_level('info');
repeat_each(1);

plan tests => repeat_each() * (blocks() * 6 - 1);

my $pwd = cwd();

no_long_string();

check_accum_error_log();
run_tests();

__DATA__

=== TEST 1: sanity
--- http_config
    lua_shared_dict request_counter 1m;
    upstream my_upstream {
        server 127.0.0.1;
        balancer_by_lua_block {
            local balancer = require "ngx.balancer"

            if not ngx.ctx.tries then
                ngx.ctx.tries = 0
            end

            ngx.ctx.tries = ngx.ctx.tries + 1
            ngx.log(ngx.INFO, "tries ", ngx.ctx.tries)

            if ngx.ctx.tries == 1 then
                balancer.set_more_tries(5)
            end

            local host = "127.0.0.1"
            local port = $TEST_NGINX_RAND_PORT_1;

            local ok, err = balancer.set_current_peer(host, port)
            if not ok then
                ngx.log(ngx.ERR, "failed to set the current peer: ", err)
                return ngx.exit(500)
            end

            balancer.set_timeouts(60000, 60000, 60000)

            local ok, err = balancer.enable_keepalive(60, 100)
            if not ok then
                ngx.log(ngx.ERR, "failed to enable keepalive: ", err)
                return ngx.exit(500)
            end
        }
    }

    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1;
        location /hello {
            content_by_lua_block{
                local request_counter = ngx.shared.request_counter
                local first_request = request_counter:get("first_request")
                if first_request == nil then
                    request_counter:set("first_request", "yes")
                    ngx.print("hello")
                else
                    ngx.exit(ngx.HTTP_CLOSE)
                end
            }
        }
    }
--- config
    location = /t {
        proxy_pass http://my_upstream;
        proxy_set_header Connection "keep-alive";

        rewrite_by_lua_block {
           ngx.req.set_uri("/hello")
        }
    }
--- pipelined_requests eval
["GET /t HTTP/1.1" , "GET /t HTTP/1.1"]
--- response_body eval
["hello", qr/502/]
--- error_code eval
[200, 502]
--- no_error_log eval
qr/tries 7/



=== TEST 2: set_more_tries does not wrap after cached connection errors
Without the Nginx cached-connection-error notification patch, four cached
connections are enough to drive total beyond proxy_next_upstream_tries.
The fix allows six attempts (four cached and two fresh); with the notification
patch the request stops after three. Neither case may wrap the retry budget.
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";
    lua_shared_dict warm_counter 1m;

    proxy_next_upstream_tries 3;
    upstream backend {
        server 0.0.0.1;
        keepalive 4;
        balancer_by_lua_block {
            local b = require "ngx.balancer"
            local n = (ngx.ctx.n or 0) + 1
            ngx.ctx.n = n
            ngx.log(ngx.INFO, "balancer ", ngx.var.uri, " invocation ", n)

            -- This is the pattern used by ingress-nginx: grant one extra
            -- attempt every time the balancer is entered, including retries.
            -- Allow the six bounded attempts even without the Nginx patch,
            -- but stop a wrapped retry budget before the test times out.
            if n > 6 then
                ngx.log(ngx.ERR, "retry storm guard")
                return ngx.exit(500)
            end

            local ok, err = b.set_more_tries(1)
            if not ok then
                error("failed to set more tries: " .. err)
            end

            if err then
                ngx.log(ngx.WARN, "set_more_tries: ", err)
            end

            local ok, err = b.set_current_peer("127.0.0.1",
                                              $TEST_NGINX_RAND_PORT_1)
            if not ok then
                error("failed to set current peer: " .. err)
            end
        }
    }

    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1;

        location = /warm {
            content_by_lua_block {
                local counter = ngx.shared.warm_counter
                local n = counter:incr("requests", 1)
                local deadline = ngx.now() + 2

                -- Hold each response until all four upstream connections
                -- are open, so the warm-up cannot reuse a single connection.
                while n < 4 do
                    if ngx.now() >= deadline then
                        return ngx.exit(504)
                    end

                    ngx.sleep(0.01)
                    n = counter:get("requests")
                end

                ngx.say("ok")
            }
        }

        location / {
            return 444;
        }
    }
--- config
    location = /t {
        content_by_lua_block {
            ngx.shared.warm_counter:set("requests", 0)

            local responses = { ngx.location.capture_multi({
                { "/warm" },
                { "/warm" },
                { "/warm" },
                { "/warm" },
            }) }

            for i = 1, 4 do
                local res = responses[i]
                if res.status ~= 200 or res.body ~= "ok\n" then
                    error("warm-up failed: " .. res.status .. ": " .. res.body)
                end
            end

            ngx.say("warm-up: 4")
            local res = ngx.location.capture("/bad")
            ngx.say("status: ", res.status)
        }
    }

    location = /warm {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }

    location = /bad {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_next_upstream error timeout;
        proxy_next_upstream_timeout 0;
    }
--- request
GET /t
--- response_body
warm-up: 4
status: 502
--- grep_error_log eval: qr/balancer \/bad invocation \d+\b/
--- grep_error_log_out eval
my $first = CORE::join "", map { "balancer /bad invocation $_\n" } 1 .. 3;
my $extra = CORE::join "", map { "balancer /bad invocation $_\n" } 4 .. 6;
qr/\A\Q$first\E(?:\Q$extra\E)?\z/
--- no_error_log
retry storm guard
[alert]
