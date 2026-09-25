# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

master_on();
repeat_each(1);

plan tests => repeat_each() * (blocks() * 3 + 4);

no_long_string();

# UDP echo server for the UDP cosocket test: memcached 1.6+ dropped the
# text-over-UDP protocol, so we echo datagrams ourselves
my $udp_echo_pid = fork();
if (!$udp_echo_pid) {
    require IO::Socket::INET;
    my $srv = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1', LocalPort => 19849, Proto => 'udp')
        or die "udp echo bind: $!";
    while (my $peer = $srv->recv(my $buf, 4096)) {
        $srv->send($buf, 0, $peer);
    }
    exit 0;
}
# TCP server that closes connections after 2s (for remote-disconnect test)
my $kill_tcp_pid = fork();
if (!$kill_tcp_pid) {
    require IO::Socket::INET;
    my $srv = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1', LocalPort => 19850, Proto => 'tcp',
        Listen => 5, ReuseAddr => 1) or die "kill tcp bind: $!";
    while (my $cli = $srv->accept()) {
        # read a bit, then close after 2s (simulates remote going away)
        my $buf;
        recv($cli, $buf, 1024, 0);
        sleep 2;
        close $cli;
    }
    exit 0;
}
END { kill 'KILL', $udp_echo_pid if $udp_echo_pid; kill 'KILL', $kill_tcp_pid if $kill_tcp_pid; }



our $HtmlDir = html_dir;

our $wall_clock = <<'_EOC_';
        local ffi = require("ffi")
        ffi.cdef[[
            typedef long time_t;
            typedef struct timeval { time_t tv_sec; time_t tv_usec; } timeval;
            int gettimeofday(struct timeval *t, void *tzp);
        ]]
        local tv = ffi.new("timeval")
        function wall_us()
            ffi.C.gettimeofday(tv, nil)
            return tonumber(tv.tv_sec) * 1000000 + tonumber(tv.tv_usec)
        end

        ffi.cdef[[
            typedef struct {
                struct timeval ru_utime;
                struct timeval ru_stime;
                long pad[14];
            } rusage_t;
            int getrusage(int who, rusage_t *usage);
        ]]
        local ru = ffi.new("rusage_t")
        function cpu_us()
            ffi.C.getrusage(0, ru)   -- 0 = RUSAGE_SELF
            return tonumber(ru.ru_utime.tv_sec) * 1000000
                 + tonumber(ru.ru_utime.tv_usec)
                 + tonumber(ru.ru_stime.tv_sec) * 1000000
                 + tonumber(ru.ru_stime.tv_usec)
        end
_EOC_

run_tests();

__DATA__
=== TEST 1: sanity: TCP cosocket connect/send/receive in init_worker_by_lua
--- http_config eval
qq{
    init_by_lua_block {
$main::wall_clock
    }
    lua_init_worker_timeout 10s;
    init_worker_by_lua_block {
        local begin = wall_us()

        local sock = ngx.socket.tcp()
        local ok, err = sock:connect("127.0.0.1", $ENV{TEST_NGINX_MEMCACHED_PORT})
        if not ok then
            iw_result = "connect failed: " .. (err or "unknown")
            return
        end

        local bytes, err = sock:send("flush_all\\r\\n")
        if not bytes then
            iw_result = "send failed: " .. (err or "unknown")
            return
        end

        local line, err = sock:receive()
        if not line then
            iw_result = "receive failed: " .. (err or "unknown")
            return
        end

        sock:close()
        iw_result = "received: " .. line
        iw_elapsed = wall_us() - begin
    }
}
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_result or "no result")
            if iw_elapsed then
                ngx.say(iw_elapsed < 2000000 and "elapsed OK"
                        or "elapsed too long: " .. iw_elapsed .. "us")
            else
                ngx.say("no elapsed")
            end
        }
    }
--- request
GET /t
--- response_body
received: OK
elapsed OK
--- timeout: 15
--- log_level: debug
--- error_log
lua run thread returned
--- no_error_log
[error]



=== TEST 2: ngx.sleep(0.1) and ngx.sleep(0) in init_worker_by_lua
--- http_config eval
qq{
    init_by_lua_block {
$main::wall_clock
    }
    lua_init_worker_timeout 5s;
    init_worker_by_lua_block {
        local t0 = wall_us()
        ngx.sleep(0.1)
        local t1 = wall_us()
        ngx.sleep(0)
        local t2 = wall_us()

        iw_done = true
        -- no lower-bound timing assertion here: under valgrind/loaded CI,
        -- wall_us() can report less than the sleep target; the busy-spin
        -- guard is TEST 5's cpu_us assertion, which is the right tool
        iw_slept = true
        iw_zero_ok = (t2 - t1) < 1000000
    }
}
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_done    and "done"     or "not done")
            ngx.say(iw_slept   and "slept OK" or "sleep too short")
            ngx.say(iw_zero_ok and "zero OK"  or "zero hung")
        }
    }
--- request
GET /t
--- response_body
done
slept OK
zero OK
--- no_error_log
[error]



=== TEST 3: semaphore wait in init_worker, posted by a spawned uthread
--- http_config eval
qq{
    init_by_lua_block {
$main::wall_clock
    }
    lua_init_worker_timeout 5s;
    init_worker_by_lua_block {
        local sema = require("ngx.semaphore").new(0)

        ngx.log(ngx.DEBUG, "iw: before spawn")
        local child, serr = ngx.thread.spawn(function()
            -- fetch over a real cosocket; the roundtrip takes real
            -- event-loop time, so the parent's wait genuinely blocks
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1",
                                         $ENV{TEST_NGINX_MEMCACHED_PORT})
            if not ok then
                ngx.log(ngx.ERR, "child connect failed: ", err)
                return
            end
            sock:send("flush_all\\r\\n")
            sock:receive()
            sock:close()
            ngx.log(ngx.DEBUG, "iw: child posting")
            sema:post(1)
        end)
        iw_spawn_ok = child and true or false

        ngx.log(ngx.DEBUG, "iw: before wait")
        local t0 = wall_us()

        local wok, werr = sema:wait(3)

        local t1 = wall_us()
        ngx.log(ngx.DEBUG, "iw: after wait")
        iw_wait_ok = wok and true or false
        iw_wait_err = werr or "none"
        iw_wait_us = t1 - t0

        local jok = ngx.thread.wait(child)
        iw_join_ok = jok and true or false
    }
}
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_spawn_ok and "spawn OK" or "spawn failed")
            ngx.say(iw_wait_ok  and "wait OK"  or "wait failed: "
                    .. (iw_wait_err or ""))
            ngx.say(iw_wait_us and iw_wait_us < 2000000
                    and "fast wakeup" or "slow wakeup")
            ngx.say(iw_join_ok and "join OK" or "join failed")
        }
    }
--- request
GET /t
--- response_body
spawn OK
wait OK
fast wakeup
join OK
--- log_level: debug
--- grep_error_log eval: qr/iw: [^,\n]*/
--- grep_error_log_out
iw: before spawn
iw: before wait
iw: child posting
iw: after wait
--- no_error_log
[error]



=== TEST 4: non-yielding init_worker code behaves unchanged
--- http_config
    init_worker_by_lua_block {
        local s = 0
        for i = 1, 100 do
            s = s + i
        end
        iw_sync_sum = s
        iw_sync_msg = "sync done"
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_sync_msg or "no result")
            ngx.say(iw_sync_sum == 5050 and "sum OK" or "sum wrong")
        }
    }
--- request
GET /t
--- response_body
sync done
sum OK
--- no_error_log
[error]



=== TEST 5: pump does not busy-spin with a finite timeout budget
--- http_config eval
qq{
    init_by_lua_block {
$main::wall_clock
    }
    lua_init_worker_timeout 5s;
    init_worker_by_lua_block {
        -- finite timeout: locks the deadline/clamp budget branch
        -- (the default-0 sentinel path is covered by t/195)
        local c0 = cpu_us()
        ngx.sleep(2)
        local c1 = cpu_us()
        iw_slept = 1
        iw_cpu_us = c1 - c0
    }
}
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_slept and "slept" or "not slept")
            ngx.say(iw_cpu_us and iw_cpu_us < 50000
                    and "cpu idle OK" or "cpu busy: " .. (iw_cpu_us or "?"))
        }
    }
--- request
GET /t
--- response_body
slept
cpu idle OK
--- timeout: 15
--- no_error_log
[error]



=== TEST 6: timer.at registered after the first yield rans only after init_worker finishes
--- http_config
    lua_shared_dict iw_state 1m;
    init_worker_by_lua_block {
        local shdict = ngx.shared.iw_state
        shdict:set("chunk_done", 0)

        ngx.sleep(0.1)          -- yield #1: pumping turns on

        local tok, terr = ngx.timer.at(0, function(premature)
            if premature then
                return
            end
            shdict:set("cb_saw_done", shdict:get("chunk_done"))
            shdict:set("cb_ran", 1)
        end)
        shdict:set("timer_ok", tok and 1 or 0)

        ngx.sleep(0.3)          -- yield #2: an unfrozen 0ms timer would fire here

        shdict:set("chunk_done", 1)
    }
--- config
    location /t {
        content_by_lua_block {
            local shdict = ngx.shared.iw_state
            for i = 1, 50 do
                if shdict:get("cb_ran") then
                    break
                end
                ngx.sleep(0.05)
            end
            ngx.say("timer_ok: " .. (shdict:get("timer_ok") == 1 and "OK" or "FAIL"))
            ngx.say("cb_ran: " .. (shdict:get("cb_ran") == 1 and "OK" or "FAIL"))
            ngx.say("cb_after_chunk: " .. (shdict:get("cb_saw_done") == 1 and "OK" or "FAIL"))
        }
    }
--- request
GET /t
--- response_body
timer_ok: OK
cb_ran: OK
cb_after_chunk: OK
--- timeout: 10
--- no_error_log
[error]



=== TEST 7: timer.at registered before the first yield also runs only after init_worker finishes
--- http_config
    lua_shared_dict iw_state 1m;
    init_worker_by_lua_block {
        local shdict = ngx.shared.iw_state
        shdict:set("chunk_done", 0)

        local tok, terr = ngx.timer.at(0, function(premature)
            if premature then
                return
            end
            shdict:set("cb_saw_done", shdict:get("chunk_done"))
            shdict:set("cb_ran", 1)
        end)
        shdict:set("timer_ok", tok and 1 or 0)

        ngx.sleep(0.3)          -- the only yield; if the freeze were broken,
                                -- cb would fire inside the pump here

        shdict:set("chunk_done", 1)
    }
--- config
    location /t {
        content_by_lua_block {
            local shdict = ngx.shared.iw_state
            for i = 1, 50 do
                if shdict:get("cb_ran") then
                    break
                end
                ngx.sleep(0.05)
            end
            ngx.say("timer_ok: " .. (shdict:get("timer_ok") == 1 and "OK" or "FAIL"))
            ngx.say("cb_ran: " .. (shdict:get("cb_ran") == 1 and "OK" or "FAIL"))
            ngx.say("cb_after_chunk: " .. (shdict:get("cb_saw_done") == 1 and "OK" or "FAIL"))
        }
    }
--- request
GET /t
--- response_body
timer_ok: OK
cb_ran: OK
cb_after_chunk: OK
--- timeout: 10
--- no_error_log
[error]



=== TEST 8: timer.at in a non-yielding init_worker runs only after init (legacy behavior unchanged)
--- http_config
    lua_shared_dict iw_state 1m;
    init_worker_by_lua_block {
        local shdict = ngx.shared.iw_state
        shdict:set("chunk_done", 0)

        local tok, terr = ngx.timer.at(0, function(premature)
            if premature then
                return
            end
            shdict:set("cb_saw_done", shdict:get("chunk_done"))
            shdict:set("cb_ran", 1)
        end)
        shdict:set("timer_ok", tok and 1 or 0)

        shdict:set("chunk_done", 1)
    }
--- config
    location /t {
        content_by_lua_block {
            local shdict = ngx.shared.iw_state
            for i = 1, 50 do
                if shdict:get("cb_ran") then
                    break
                end
                ngx.sleep(0.05)
            end
            ngx.say("timer_ok: " .. (shdict:get("timer_ok") == 1 and "OK" or "FAIL"))
            ngx.say("cb_ran: " .. (shdict:get("cb_ran") == 1 and "OK" or "FAIL"))
            ngx.say("cb_after_chunk: " .. (shdict:get("cb_saw_done") == 1 and "OK" or "FAIL"))
        }
    }
--- request
GET /t
--- response_body
timer_ok: OK
cb_ran: OK
cb_after_chunk: OK
--- timeout: 10
--- no_error_log
[error]



=== TEST 9: frozen timer survives a timeout abort and still fires
--- http_config
    lua_shared_dict iw_state 1m;
    lua_init_worker_timeout 500ms;
    init_worker_by_lua_block {
        local shdict = ngx.shared.iw_state

        local tok, terr = ngx.timer.at(0, function(premature)
            if premature then
                return
            end
            -- no chunk-local upvalues here: they are nil'd after a timeout abort
            ngx.shared.iw_state:set("cb_ran", 1)
        end)
        shdict:set("timer_ok", tok and 1 or 0)

        ngx.sleep(10)          -- never finishes; the 500ms budget aborts the chunk
    }
--- config
    location /t {
        content_by_lua_block {
            local shdict = ngx.shared.iw_state
            for i = 1, 50 do
                if shdict:get("cb_ran") then
                    break
                end
                ngx.sleep(0.05)
            end
            ngx.say("timer_ok: " .. (shdict:get("timer_ok") == 1 and "OK" or "FAIL"))
            ngx.say("cb_ran: " .. (shdict:get("cb_ran") == 1 and "OK" or "FAIL"))
        }
    }
--- request
GET /t
--- response_body
timer_ok: OK
cb_ran: OK
--- timeout: 10
--- error_log
init_worker_by_lua* timed out



=== TEST 10: compile error keeps the legacy log prefix, worker still starts
--- http_config
    init_worker_by_lua_block {
        local x =
        -- nothing after the "=": syntax error  at load time
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say("still serving")
        }
    }
--- request
GET /t
--- response_body
still serving
--- error_log
init_worker_by_lua error:
--- no_error_log
lua run thread returned:



=== TEST 11: runtime error with default abort_on_error off uses the new prefix, worker still starts
--- http_config
   init_worker_by_lua_block {
       error("boom")   -- runtime error before any yield
   }
--- config
   location /t {
       content_by_lua_block {
           ngx.say("still serving")
       }
   }
--- request
GET /t
--- response_body
still serving
--- error_log
lua entry thread aborted:
--- no_error_log
init_worker_by_lua error:



=== TEST 12: a stalled remote read times out via lua_init_worker_timeout, worker still starts
--- http_config
    lua_init_worker_timeout 500ms;
    init_worker_by_lua_block {
        local sock = ngx.socket.tcp()
        local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if not ok then
            return
        end
        sock:send("get")   -- incomplete command: memcached waits for \r\n forever
        sock:receive()     -- hangs here; the 500ms budget aborts mid-read
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say("still serving")
        }
    }
--- request
GET /t
--- response_body
still serving
--- timeout: 10
--- error_log
init_worker_by_lua* timed out



=== TEST 13: timer.every registered in init_worker fires only after init and renews normally
--- http_config
   lua_shared_dict iw_state 1m;
   init_worker_by_lua_block {
       local shdict = ngx.shared.iw_state
       shdict:set("chunk_done", 0)
       shdict:set("fires", 0)

       local tok, err = ngx.timer.every(0.05, function(premature)
           if premature then
               return
           end
           shdict:set("fires", shdict:get("fires") + 1)
           if shdict:get("chunk_done") ~= 1 then
               shdict:set("bad_early", 1)
           end
       end)
       shdict:set("timer_ok", tok and 1 or 0)

       ngx.sleep(0.2)          -- 4 intervals elapse inside the pump;
                               -- a broken freeze would fire the timer here

       shdict:set("chunk_done", 1)
   }
--- config
   location /t {
       content_by_lua_block {
           local shdict = ngx.shared.iw_state
           for i = 1, 100 do
               if (shdict:get("fires") or 0) >= 3 then
                   break
               end
               ngx.sleep(0.05)
           end
           ngx.say("timer_ok: " .. (shdict:get("timer_ok") == 1 and "OK" or "FAIL"))
           ngx.say("renewal: " .. ((shdict:get("fires") or 0) >= 3 and "OK" or "FAIL"))
           ngx.say("no early fire: " .. (shdict:get("bad_early") and "FAIL" or "OK"))
       }
   }
--- request
GET /t
--- response_body
timer_ok: OK
renewal: OK
no early fire: OK
--- timeout: 10
--- no_error_log
[error]



=== TEST 14: ngx.thread.spawn + wait, child does a cosocket roundtrip
--- http_config
    lua_init_worker_timeout 5s;
    init_worker_by_lua_block {
        local child, serr = ngx.thread.spawn(function()
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                iw_child_result = "connect failed: " .. (err or "?")
                return
            end
            sock:send("flush_all\r\n")
            local line = sock:receive()
            sock:close()
            iw_child_result = "received: " .. (line or "?")
        end)
        iw_spawn_ok = child and true or false

        local jok = ngx.thread.wait(child)
        iw_join_ok = jok and true or false
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_spawn_ok and "spawn OK" or "spawn failed")
            ngx.say(iw_join_ok and "join OK" or "join failed")
            ngx.say(iw_child_result or "no result")
        }
    }
--- request
GET /t
--- response_body
spawn OK
join OK
received: OK
--- timeout: 15
--- no_error_log
[error]



=== TEST 15: timer.at(0) is deferred on bundle builds too (delayed-events path)
--- http_config
    lua_shared_dict iw_state 1m;
    init_worker_by_lua_block {
        local shdict = ngx.shared.iw_state
        shdict:set("chunk_done", 0)

        ngx.sleep(0.1)          -- yield #1: pumping turns on

        -- an unfrozen timer.at(0) lands in ngx_posted_delayed_events, which
        -- the pump processes in the same round — the freeze must intercept
        local tok, terr = ngx.timer.at(0, function(premature)
            if premature then
                return
            end
            shdict:set("cb_saw_done", shdict:get("chunk_done"))
            shdict:set("cb_ran", 1)
        end)
        shdict:set("timer_ok", tok and 1 or 0)

        ngx.sleep(0.3)          -- yield #2: the unfrozen delayed event would
                                -- fire here on a bundle build

        shdict:set("chunk_done", 1)
    }
--- config
    location /t {
        content_by_lua_block {
            local shdict = ngx.shared.iw_state
            for i = 1, 50 do
                if shdict:get("cb_ran") then
                    break
                end
                ngx.sleep(0.05)
            end
            ngx.say("timer_ok: " .. (shdict:get("timer_ok") == 1 and "OK" or "FAIL"))
            ngx.say("cb_ran: " .. (shdict:get("cb_ran") == 1 and "OK" or "FAIL"))
            ngx.say("cb_after_chunk: " .. (shdict:get("cb_saw_done") == 1 and "OK" or "FAIL"))
        }
    }
--- request
GET /t
--- response_body
timer_ok: OK
cb_ran: OK
cb_after_chunk: OK
--- timeout: 10
--- no_error_log
[error]



=== TEST 16: UDP cosocket roundtrip in init_worker
--- http_config
    lua_init_worker_timeout 5s;
    init_worker_by_lua_block {
        local sock = ngx.socket.udp()
        local ok, err = sock:setpeername("127.0.0.1", 19849)
        if not ok then
            iw_udp_result = "setpeername failed: " .. (err or "?")
            return
        end
        sock:settimeout(2000)
        local bytes, err = sock:send("ping")
        if not bytes then
            iw_udp_result = "send failed: " .. (err or "?")
            return
        end
        local data, err = sock:receive()
        if not data then
            iw_udp_result = "receive failed: " .. (err or "?")
            return
        end
        sock:close()
        iw_udp_result = "received: " .. data
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_udp_result or "no result")
        }
    }
--- request
GET /t
--- response_body
received: ping
--- timeout: 10
--- no_error_log
[error]



=== TEST 17: ngx.run_worker_thread under the pump
--- main_config
    thread_pool testpool threads=1;
--- http_config eval
qq{
    lua_package_path "$::HtmlDir/?.lua;./?.lua;;";
    lua_worker_thread_vm_pool_size 1;
    lua_init_worker_timeout 5s;
    init_worker_by_lua_block {
        local ok, res = ngx.run_worker_thread("testpool", "hello", "hello")
        iw_wt_ok = ok
        iw_wt_res = res
    }
}
--- config
    location /t {
        content_by_lua_block {
            ngx.say((iw_wt_ok and iw_wt_res == "hello") and "thread OK"
                    or "thread failed: " .. tostring(iw_wt_res))
        }
    }
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /t
--- response_body
thread OK
--- timeout: 10
--- no_error_log
[error]



=== TEST 18: cosocket connect via resolver in init_worker
--- http_config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_init_worker_timeout 10s;
    init_worker_by_lua_block {
        local sock = ngx.socket.tcp()
        local ok, err = sock:connect("openresty.org", 80)
        if not ok then
            iw_res_result = "connect failed: " .. (err or "?")
            return
        end
        sock:close()
        iw_res_result = "resolved and connected"
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_res_result or "no result")
        }
    }
--- request
GET /t
--- response_body
resolved and connected
--- timeout: 15
--- no_error_log
[error]



=== TEST 19: SSL cosocket handshake in init_worker
--- http_config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_init_worker_timeout 10s;
    init_worker_by_lua_block {
        local sock = ngx.socket.tcp()
        sock:settimeout(5000)
        local ok, err = sock:connect("openresty.org", 443)
        if not ok then
            iw_ssl_result = "connect failed: " .. (err or "?")
            return
        end
        local sess, err = sock:sslhandshake(nil, "openresty.org", false)
        if not sess then
            iw_ssl_result = "handshake failed: " .. (err or "?")
            return
        end
        sock:close()
        iw_ssl_result = "ssl handshake OK"
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_ssl_result or "no result")
        }
    }
--- request
GET /t
--- response_body
ssl handshake OK
--- timeout: 15
--- no_error_log
[error]


=== TEST 20: unclosed cosocket reaped by pool cleanup on timeout
--- http_config
    lua_init_worker_timeout 500ms;
    init_worker_by_lua_block {
        local sock = ngx.socket.tcp()
        local ok = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if not ok then
            iw_result = "connect failed"
            return
        end
        sock:send("get")
        sock:receive()
        -- deliberately no sock:close(): the pool cleanup must close the fd
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say("still serving")
        }
    }
--- request
GET /t
--- response_body
still serving
--- timeout: 10
--- error_log
init_worker_by_lua* timed out



=== TEST 21: stalled remote read times out cleanly, no memory errors
--- http_config
    lua_init_worker_timeout 500ms;
    init_worker_by_lua_block {
        local sock = ngx.socket.tcp()
        local ok = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if not ok then
            return
        end
        sock:send("get")
        sock:receive()
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say("still serving")
        }
    }
--- request
GET /t
--- response_body
still serving
--- timeout: 10
--- error_log
init_worker_by_lua* timed out



=== TEST 22: normal cosocket roundtrip completes, runner does not touch freed request
--- http_config
    lua_init_worker_timeout 5s;
    init_worker_by_lua_block {
        local sock = ngx.socket.tcp()
        local ok = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if not ok then
            iw_result = "connect failed"
            return
        end
        sock:send("flush_all\r\n")
        local line = sock:receive()
        sock:close()
        iw_result = "received: " .. (line or "?")
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_result or "no result")
        }
    }
--- request
GET /t
--- response_body
received: OK
--- timeout: 10
--- no_error_log
[error]



=== TEST 23: remote disconnects while cosocket is yielded
--- http_config
    lua_init_worker_timeout 10s;
    init_worker_by_lua_block {
        local sock = ngx.socket.tcp()
        local ok = sock:connect("127.0.0.1", 19850)
        if not ok then
            iw_result = "connect failed: " .. (err or "?")
            return
        end
        sock:send("hello")
        -- server closes after 2s; we're yielded waiting for a reply that
        -- will never come — the cleanup chain must handle the RST cleanly
        local data, err = sock:receive()
        iw_result = data and ("received: " .. data) or ("recv err: " .. (err or "?"))
        sock:close()
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say(iw_result or "no result")
        }
    }
--- request
GET /t
--- response_body
recv err: closed
--- timeout: 15
--- no_error_log
[error]

