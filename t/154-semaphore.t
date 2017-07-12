# vim:set ft=ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(10140);
#workers(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3) + blocks();

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: timer + shutdown error log
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";

    init_by_lua_block {
        require "resty.core"
    }
--- config
    location /test {
        content_by_lua_block {
            local function test(pre)

                local semaphore = require "ngx.semaphore"
                local sem = semaphore.new()

                local function sem_wait()

                    local ok, err = sem:wait(10)
                    if not ok then
                        ngx.log(ngx.ERR, "err: ", err)
                    else
                        ngx.log(ngx.ERR, "wait success")
                    end
                end

                while not ngx.worker.exiting() do
                    local co = ngx.thread.spawn(sem_wait)
                    ngx.thread.wait(co)
                end
            end

            local ok, err = ngx.timer.at(0, test)
            ngx.log(ngx.ERR, "hello, world")
            ngx.say("time: ", ok)
        }
    }
--- request
GET /test
--- response_body
time: 1
--- grep_error_log eval: qr/hello, world|semaphore gc wait queue is not empty/
--- grep_error_log_out
hello, world
--- shutdown_error_log
--- no_shutdown_error_log
semaphore gc wait queue is not empty



=== TEST 2: timer + shutdown error log (lua code cache off)
--- http_config
    lua_code_cache off;
    lua_package_path "../lua-resty-core/lib/?.lua;;";

    init_by_lua_block {
        require "resty.core"
    }
--- config
    location /test {
        content_by_lua_block {
            local function test(pre)

                local semaphore = require "ngx.semaphore"
                local sem = semaphore.new()

                local function sem_wait()

                    local ok, err = sem:wait(10)
                    if not ok then
                        ngx.log(ngx.ERR, "err: ", err)
                    else
                        ngx.log(ngx.ERR, "wait success")
                    end
                end

                while not ngx.worker.exiting() do
                    local co = ngx.thread.spawn(sem_wait)
                    ngx.thread.wait(co)
                end
            end

            local ok, err = ngx.timer.at(0, test)
            ngx.log(ngx.ERR, "hello, world")
            ngx.say("time: ", ok)
        }
    }
--- request
GET /test
--- response_body
time: 1
--- grep_error_log eval: qr/hello, world|semaphore gc wait queue is not empty/
--- grep_error_log_out
hello, world
--- shutdown_error_log
--- no_shutdown_error_log
semaphore gc wait queue is not empty
