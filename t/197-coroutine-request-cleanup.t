# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);
workers(1);
log_level('debug');
no_long_string();

plan tests => repeat_each() * blocks() * 5;

run_tests();

__DATA__

=== TEST 1: client abort cleans a pending sleep in an ordinary coroutine
--- skip_eval: 5: $ENV{TEST_NGINX_USE_HTTP2} || $ENV{TEST_NGINX_USE_HTTP3}
--- http_config
    lua_shared_dict coroutine_cleanup 1m;
--- config
    location = /victim {
        lua_check_client_abort on;
        content_by_lua_block {
            local co = coroutine.create(function()
                ngx.header.content_length = 6
                ngx.say("ready")
                assert(ngx.flush(true))
                assert(ngx.shared.coroutine_cleanup:set("pending", true))
                ngx.sleep(10)
                error("aborted coroutine resumed")
            end)
            local ok, err = coroutine.resume(co)
            assert(ok, err)
        }

        log_by_lua_block {
            assert(ngx.shared.coroutine_cleanup:set("finished", true))
        }
    }

    location = /t {
        content_by_lua_block {
            local state = ngx.shared.coroutine_cleanup
            state:delete("pending")
            state:delete("finished")

            local sock = ngx.socket.tcp()
            sock:settimeout(2000)
            assert(sock:connect("127.0.0.1", tonumber(ngx.var.server_port)))
            assert(sock:send("GET /victim HTTP/1.1\r\nHost: localhost\r\n"
                            .. "Connection: close\r\n\r\n"))
            assert(sock:receive() == "HTTP/1.1 200 OK")
            while assert(sock:receive()) ~= "" do
                -- Consume the response headers before reading the barrier.
            end

            assert(sock:receive(6) == "ready\n")
            local deadline = ngx.now() + 2
            while not state:get("pending") do
                assert(ngx.now() < deadline, "ordinary coroutine did not sleep")
                ngx.sleep(0.001)
            end

            -- With one worker, the child has installed its timer before this
            -- request can observe pending and close the real HTTP connection.
            assert(sock:close())
            while not state:get("finished") do
                assert(ngx.now() < deadline, "aborted request was not finalized")
                ngx.sleep(0.001)
            end

            -- Touch the timer tree again after the victim's request pool was
            -- freed. ASan also detects a stale node here without the fix.
            ngx.sleep(0.001)
            ngx.say("client abort cleanup: OK")
        }
    }
--- request
GET /t
--- response_body
client abort cleanup: OK
--- grep_error_log eval: qr/lua clean up the timer for pending ngx\.sleep/
--- grep_error_log_out
lua clean up the timer for pending ngx.sleep
--- no_error_log
[error]
[alert]



=== TEST 2: request exit cleans a pending sleep under six ordinary coroutines
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";
--- config
    location = /t {
        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local ready = semaphore.new()
            ngx.thread.spawn(function()
                assert(ready:wait(2))
                ngx.say("request exit cleanup: OK")
                ngx.exit(200)
            end)

            local function sleep(depth)
                if depth == 0 then
                    -- Posting wakes the exit thread on its next event-loop
                    -- turn, after this coroutine has installed its timer.
                    ready:post()
                    ngx.sleep(10)
                    error("exited coroutine resumed")
                end

                local co = coroutine.create(sleep)
                local ok, err = coroutine.resume(co, depth - 1)
                assert(ok, err)
            end

            -- Cross the initial four-element user_co_ctx list allocation.
            sleep(6)
        }
    }
--- request
GET /t
--- response_body
request exit cleanup: OK
--- grep_error_log eval: qr/lua clean up the timer for pending ngx\.sleep/
--- grep_error_log_out
lua clean up the timer for pending ngx.sleep
--- no_error_log
[error]
[alert]
