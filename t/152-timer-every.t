# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 7 + 2);

#no_diff();
no_long_string();

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;

worker_connections(1024);
run_tests();

__DATA__

=== TEST 1: simple very
--- config
    location /t {
        content_by_lua_block {
            local begin = ngx.now()
            local ticks = 0
            local function f(premature)
                if ticks >= 2 then
                    return
                end

                ticks = ticks + 1
                print("tick ", ticks, ", delay respected: ",
                      ngx.now() - begin >= ticks * 0.04)
                print("timer prematurely expired: ", premature)
            end

            local ok, err = ngx.timer.every(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end

            ngx.say("registered timer")
            local deadline = ngx.now() + 5
            while not (ticks == 2) do
                if ngx.now() >= deadline then
                    error("timer did not fire")
                end

                ngx.sleep(0.01)
            end
        }
    }
--- request
GET /t
--- response_body
registered timer
--- wait: 0.11
--- no_error_log
[error]
[alert]
[crit]
timer prematurely expired: true
--- error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: tick 1, delay respected: true, context: ngx\.timer, client: \d+\.\d+\.\d+\.\d+, server: 0\.0\.0\.0:\d+/,
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: tick 2, delay respected: true, context: ngx\.timer, client: \d+\.\d+\.\d+\.\d+, server: 0\.0\.0\.0:\d+/,
"lua ngx.timer expired",
"http lua close fake http connection",
"timer prematurely expired: false",
]



=== TEST 2: shared global env
--- config
    location /t {
        content_by_lua_block {
            local begin = ngx.now()
            local function f()
                foo = 3
                print("foo in timer: ", foo)
            end
            local ok, err = ngx.timer.every(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            local deadline = ngx.now() + 5
            while not (foo == 3) do
                if ngx.now() >= deadline then
                    error("timer did not fire")
                end

                ngx.sleep(0.01)
            end
            ngx.say("foo = ", foo)
        }
    }
--- request
GET /t
--- response_body
foo = 3
--- wait: 0.12
--- no_error_log
[error]
[alert]
[crit]
--- error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: foo in timer: 3/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 3: lua variable sharing via upvalue
--- config
    location /t {
        content_by_lua_block {
            local begin = ngx.now()
            local foo = 0
            local function f()
                if foo >= 6 then
                    return
                end

                foo = foo + 3
                print("foo in timer: ", foo)
            end
            local ok, err = ngx.timer.every(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            local deadline = ngx.now() + 5
            while not (foo == 6) do
                if ngx.now() >= deadline then
                    error("timer did not fire")
                end

                ngx.sleep(0.01)
            end
            ngx.say("foo = ", foo)
        }
    }
--- request
GET /t
--- response_body
registered timer
foo = 6
--- wait: 0.12
--- no_error_log
[error]
[alert]
[crit]
--- error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: foo in timer: 3/,
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: foo in timer: 6/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 4: create the next timer immediately when timer start running
--- config
    location /t {
        content_by_lua_block {
            local begin = ngx.now()
            local foo = 0
            local first_running = false
            local function f()
                if foo >= 6 then
                    return
                end

                foo = foo + 3
                print("foo in timer: ", foo)

                if foo == 3 then
                    first_running = true
                    local deadline = ngx.now() + 5
                    while foo < 6 do
                        if ngx.now() >= deadline then
                            error("next timer waited for the first callback")
                        end

                        ngx.sleep(0.01)
                    end

                    first_running = false

                else
                    assert(first_running, "timer callbacks did not overlap")
                end
            end
            local ok, err = ngx.timer.every(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            local deadline = ngx.now() + 5
            while not (foo == 6) do
                if ngx.now() >= deadline then
                    error("timer did not fire")
                end

                ngx.sleep(0.01)
            end
            ngx.say("foo = ", foo)
        }
    }
--- request
GET /t
--- response_body
registered timer
foo = 6
--- wait: 0.12
--- no_error_log
[error]
[alert]
[crit]
--- error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: foo in timer: 3/,
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: foo in timer: 6/,
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 5: callback args
--- config
    location /t {
        content_by_lua_block {
            local n = 0

            local function f(premature, a, b, c)
                if n >= 2 then
                    return
                end

                n = n + 1
                print("the ", n, " time, args: ", a, ", ", b, ", ", c)

                a, b, c = 0, 0, 0
            end

            local ok, err = ngx.timer.every(0.05, f, 1, 2)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end

            ngx.say("registered timer")
            local deadline = ngx.now() + 5
            while not (n == 2) do
                if ngx.now() >= deadline then
                    error("timer did not fire")
                end

                ngx.sleep(0.01)
            end
        }
    }
--- request
GET /t
--- response_body
registered timer
--- wait: 0.12
--- no_error_log
[error]
[alert]
[crit]
--- error_log eval
[
"the 1 time, args: 1, 2, nil",
"the 2 time, args: 1, 2, nil",
"lua ngx.timer expired",
"http lua close fake http connection"
]



=== TEST 6: memory leak check
--- quic_max_idle_timeout: 8
--- config
    location /t {
        content_by_lua_block {
            -- Compare the same number of live timers after every callback
            -- has warmed its coroutine cache. JIT/GC hooks add unrelated
            -- allocations to this exact Lua heap accounting check.
            jit.off()
            debug.sethook()
            local runs = {}
            for i = 1, 100 do
                runs[i] = 0
                local function f(premature)
                    if not premature then
                        runs[i] = runs[i] + 1
                    end
                end

                local ok, err = ngx.timer.every(0.1, f)
                if not ok then
                    error("failed to set timer: " .. err)
                end
            end

            local function wait_cycles(count)
                local deadline = ngx.now() + 5
                while true do
                    local ready = true
                    for i = 1, 100 do
                        if runs[i] < count then
                            ready = false
                            break
                        end
                    end

                    if ready then
                        return
                    end

                    if ngx.now() >= deadline then
                        error("timer callbacks did not complete")
                    end

                    ngx.sleep(0.01)
                end
            end

            ngx.say("registered timer")
            wait_cycles(3)
            collectgarbage("collect")
            local growth1 = collectgarbage("count")
            wait_cycles(8)
            collectgarbage("collect")
            local growth2 = collectgarbage("count")
            ngx.say("growth1 == growth2: ", growth1 == growth2)
        }
    }
--- request
GET /t
--- response_body
registered timer
growth1 == growth2: true
--- no_error_log
[error]
[alert]
[crit]
--- timeout: 8



=== TEST 7: respect lua_max_pending_timers
--- http_config
    lua_max_pending_timers 10;
--- config
    location /t {
        content_by_lua_block {
            local function f()
                local a = 1
                -- do nothing
            end

            for i = 1, 11 do
                local ok, err = ngx.timer.every(0.1, f)
                if not ok then
                    ngx.say("failed to set timer: ", err)
                    return
                end
            end

            ngx.say("registered 10 timers")
        }
    }
--- request
GET /t
--- response_body
failed to set timer: too many pending timers
--- no_error_log
[error]
[alert]
[crit]



=== TEST 8: respect lua_max_running_timers
--- http_config
    lua_max_pending_timers 100;
    lua_max_running_timers 9;
--- config
    location /t {
        content_by_lua_block {
            local function f()
                local a = 1
                ngx.sleep(0.02)
                -- do nothing
            end

            for i = 1, 10 do
                local ok, err = ngx.timer.every(0.01, f)
                if not ok then
                    ngx.say("failed to set timer: ", err)
                    return
                end
            end

            ngx.say("registered 10 timers")

            ngx.sleep(0.03)
        }
    }
--- request
GET /t
--- response_body
registered 10 timers
--- no_error_log
[error]
[crit]
--- error_log
lua_max_running_timers are not enough



=== TEST 9: lua_code_cache off
FIXME: it is know that this test case leaks memory.
so we skip it in the "check leak" testing mode.
--- http_config
    lua_code_cache off;
--- config
    location /t {
        content_by_lua_block {
            local function f()
                local a = 1
                -- do nothing
            end

            local ok, err = ngx.timer.every(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end

            collectgarbage("collect")
            ngx.say("registered timer")

            ngx.sleep(0.03)

            collectgarbage("collect")

            ngx.sleep(0.03)

            collectgarbage("collect")
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
registered timer
ok
--- no_error_log
[error]
[crit]
--- no_check_leak
