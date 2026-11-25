# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

master_on();
repeat_each(1);
workers(2);

plan tests => repeat_each() * (blocks() * 3 + 1);

no_long_string();

our $wall_clock = <<'_EOC_';
        local ffi = require("ffi")
        ffi.cdef[[
            typedef long time_t;
            typedef struct timeval { time_t tv_sec; time_t tv_usec; } timeval;
            int gettimeofday(struct timeval *t, void *tzp);
            typedef struct {
                struct timeval ru_utime;
                struct timeval ru_stime;
                long pad[14];
            } rusage_t;
            int getrusage(int who, rusage_t *usage);
        ]]
        local tv = ffi.new("timeval")
        function wall_us()
            ffi.C.gettimeofday(tv, nil)
            return tonumber(tv.tv_sec) * 1000000 + tonumber(tv.tv_usec)
        end
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
=== TEST 1: accept deferred, no crash, no spin (2 workers, EPOLLEXCLUSIVE re-arm)
--- http_config eval
qq{
    init_by_lua_block {
$main::wall_clock
    }
    init_worker_by_lua_block {
        local c0 = cpu_us()
        ngx.sleep(1)
        local c1 = cpu_us()
        iw_cpu_us = c1 - c0
    }
}
--- config
    location /t {
        content_by_lua_block {
            ngx.say("response ok")
            ngx.say(iw_cpu_us and iw_cpu_us < 50000
                    and "cpu idle OK" or "cpu busy: " .. (iw_cpu_us or "?"))
        }
    }
--- request
GET /t
--- response_body
response ok
cpu idle OK
--- timeout: 15
--- no_error_log
[error]
exited on signal
