# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

worker_connections(1014);
#master_on();
#workers(2);
#log_level('debug');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 5 + 2);

#no_diff();
no_long_string();

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;

worker_connections(1024);
run_tests();

__DATA__


=== TEST 1: simple cancel
--- config
    location /t {
        content_by_lua_block {
            local begin = ngx.now()
            local function f(premature)
                print("elapsed: ", ngx.now() - begin)
                print("timer prematurely expired: ", premature)
            end

            local hdl, err = ngx.timer.every(0.05, f)
            if not hdl then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("timer create ", hdl)
            local ok, err = ngx.timer.cancel(hdl)
            if not ok then
                ngx.say("failed to cancel timer: ", err)
                return
            end
            ngx.say("cancel timer")

            local ok, err = ngx.timer.cancel(hdl)
            if not ok then
                ngx.say("failed to cancel timer: ", err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
timer create 0
cancel timer
failed to cancel timer: timer does not exist
--- wait: 2
--- no_error_log eval
[
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0\.0(?:4[4-9]|5[0-6])\d*, context: ngx\.timer, client: \d+\.\d+\.\d+\.\d+, server: 0\.0\.0\.0:\d+/,
qr/\[lua\] content_by_lua\(nginx\.conf:\d+\):\d+: elapsed: 0\.(?:09|10)\d*, context: ngx\.timer, client: \d+\.\d+\.\d+\.\d+, server: 0\.0\.0\.0:\d+/
]



=== TEST 2: memory leak check
--- http_config
    lua_max_running_timers 200;
    lua_max_pending_timers 200;
--- config
    location /t {
        content_by_lua_block {
            local function f()
                print("timer start")
            end
            for i = 1, 100 do
                local ref, err = ngx.timer.every(0.5, f)
                if not ref then
                    ngx.say("failed to create timer: ", err)
                    return
                end
            end
            ngx.say("registered timer")
            for i = 1, 100 do
                local ok, err = ngx.timer.cancel(i-1)
                if not ok then
                    ngx.say("failed to cancel timer: ", ref, " reason ", err)
                    return
                end
            end
            ngx.say("cancel timer")

            collectgarbage("collect")
            local start = collectgarbage("count")

            ngx.sleep(3)

            collectgarbage("collect")
            local growth1 = collectgarbage("count") - start

            ngx.sleep(3)

            collectgarbage("collect")
            local growth2 = collectgarbage("count") - start

            ngx.say("growth1 == growth2: ", growth1 == growth2)
        }
    }
--- request
GET /t
--- response_body
registered timer
cancel timer
growth1 == growth2: true
--- wait: 10
--- timeout: 8
--- no_error_log eval
[
"[error]",
"[alert]",
"[crit]",
"timer start"
]



=== TEST 3: expend check
--- http_config
    lua_max_running_timers 10000;
    lua_max_pending_timers 10000;
--- config
    location /t {
        content_by_lua_block {
            local function f()
                -- do nothing
            end
            for i = 1, 1025 do
                local ok, err = ngx.timer.every(99999, f)
                if not ok then
                    ngx.say("failed to create timer, reason ", err)
                    return
                end
            end
            ngx.say("success")
        }
    }
--- request
GET /t
--- response_body
success
--- wait: 2
--- error_log eval
[
"ngx.timer.reftable",
]
--- no_error_log eval
[
"[error]",
"[alert]",
"[crit]",
]



=== TEST 4: ref order test
--- http_config
    lua_max_running_timers 1000000;
    lua_max_pending_timers 1000000;
--- config
    location /t {
        content_by_lua_block {
            local function f(premature, index)
                print("timer start at ", index)
            end

            for i = 1, 100000 do
                local ref, err = ngx.timer.every(1, f, i)
                if not ref then
                    ngx.say("failed to set timer: ", err)
                    return
                end
                if ref ~= i-1 then
                    ngx.say("ref error should be ", i-1, " but got ", ref)
                    return
                end
            end
            ngx.say("registered timer")

            for i = 1, 100000 do
                local ok, err = ngx.timer.cancel(i-1)
                if not ok then
                    ngx.say("failed to cancel timer: ", refs, " reason ", err)
                    return
                end
            end
            ngx.say("cancel timer")
        }
    }
--- request
GET /t
--- response_body
registered timer
cancel timer
--- wait: 3
--- no_error_log eval
[
"timer start at",
"[error]",
"[alert]",
"[crit]",
]



=== TEST 5: next_ref test
--- http_config
    lua_max_running_timers 20000;
    lua_max_pending_timers 20000;
--- config
    location /t {
        content_by_lua_block {
            local function f(premature, index)
                -- do nothing
            end

            for i = 1, 10000 do
                local ref, err = ngx.timer.every(100, f, i)
                if not ref then
                    ngx.say("failed to set timer: ", err)
                    return
                end 
                if ref ~= i-1 then
                    ngx.say("ref should be ", i-1, " but got ", ref)
                    return
                end
            end
            ngx.say("registered timer")
            for i = 1, 100 do
                local ref =  math.random(0, 9999)
                local ok, err = ngx.timer.cancel(ref)
                if not ok then
                    ngx.say("failed to cancel timer ", err)
                    return
                end
                local next_ref, err = ngx.timer.every(100, f)
                if not next_ref then
                    ngx.say("failed to set timer: ", err)
                    return
                end
                if ref ~= next_ref then
                    ngx.say("ref == next_ref false")   -- timer's ref will be reused if timer finished or be canceled
                    return
                end
            end
            for i = 1, 10000 do
                local next_ref_second, err = ngx.timer.every(100, f)
                if not next_ref_second then
                    ngx.say("failed to set timer: ", err)
                    return
                end
                if next_ref_second ~= 9999+i then
                    ngx.say("next_ref_second should be ", 9999+i, " but got ", next_ref_second)
                    return
                end
            end
            for i = 1, 20000 do
                local ok, err = ngx.timer.cancel(i-1)
                if not ok then
                    ngx.say("failed to cancel timer: ", refs, " reason ", err)
                    return
                end
            end
            ngx.say("cancel timer")
        }
    }
--- request
GET /t
--- response_body
registered timer
cancel timer
--- wait: 3
--- no_error_log eval
[
"[error]",
"[alert]",
"[crit]",
]



=== TEST 6: lua_max_pending_timers test
--- http_config
    lua_max_running_timers 10000;
    lua_max_pending_timers 10000;
--- config
    location /t {
        content_by_lua_block {
            local function f()
                -- do nothing
            end

            for i = 1, 10000 do
                local ref, err = ngx.timer.at(999, f, i)
                if not ref then
                    ngx.say("failed to set timer: ", err)
                    return
                end
            end
            ngx.say("registered timer")
            local before_pending_count = ngx.timer.pending_count()

            for i = 1, 5000 do
                local ok, err = ngx.timer.cancel(i-1)
                if not ok then
                    ngx.say("failed to cancel timer: ", err)
                    return
                end
            end
            ngx.sleep(1)

            local after_pending_count = ngx.timer.pending_count()
            ngx.say("before should equal to after ", before_pending_count == (after_pending_count+5000))
            for i = 5001, 10000 do
                local ok, err = ngx.timer.cancel(i-1)
                if not ok then
                    ngx.say("failed to cancel timer ", " reason ", err)
                    return
                end
            end
            ngx.say("cancel timer")
        }
    }
--- request
GET /t
--- response_body
registered timer
before should equal to after true
cancel timer
--- wait: 3
--- no_error_log eval
[
"[error]",
"[alert]",
"[crit]",
]
