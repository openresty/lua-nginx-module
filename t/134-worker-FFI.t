# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
workers(3);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: content_by_lua + ngx_http_lua_ffi_worker_pid()
--- config
    location /lua {
        content_by_lua '
        local ffi = require "ffi"
        local C = ffi.C

        ffi.cdef[[
            int ngx_http_lua_ffi_worker_pid(void);
        ]]
        
        local pid = C.ngx_http_lua_ffi_worker_pid()
        ngx.say("worker pid: ", pid)
        if pid ~= tonumber(ngx.var.pid) then
            ngx.say("worker pid is wrong.")
        else
            ngx.say("worker pid is correct.")
        end
        ';
    }
--- request
GET /lua
--- response_body_like
worker pid: \d+
worker pid is correct\.
--- no_error_log
[error]


=== TEST 2: content_by_lua + ngx_http_lua_ffi_worker_id()
--- config
    location /lua {
        content_by_lua '
        local ffi = require "ffi"
        local C = ffi.C

        ffi.cdef[[
            int ngx_http_lua_ffi_worker_id(void);
        ]]
        
        local id = C.ngx_http_lua_ffi_worker_id()
        ngx.say("worker id: ", id)
        ';
    }
--- request
GET /lua
--- response_body_like
worker id: \d+
--- no_error_log
[error]


=== TEST 3: content_by_lua + ngx_http_lua_ffi_worker_count()
--- config
    location /lua {
        content_by_lua '
        local ffi = require "ffi"
        local C = ffi.C

        ffi.cdef[[
            int ngx_http_lua_ffi_worker_count(void);
        ]]
        
        local count = C.ngx_http_lua_ffi_worker_count()
        ngx.say("worker count: ", count)
        ';
    }
--- request
GET /lua
--- response_body_like
worker count: 3
--- no_error_log
[error]


=== TEST 4: content_by_lua + ngx_http_lua_ffi_worker_exiting()
--- config
    location /lua {
        content_by_lua '
        local ffi = require "ffi"
        local C = ffi.C

        ffi.cdef[[
            int ngx_http_lua_ffi_worker_exiting(void);
        ]]
        
        local count = C.ngx_http_lua_ffi_worker_exiting()
        ngx.say("worker count: ", count)
        ';
    }
--- request
GET /lua
--- response_body_like
worker count: 0
--- no_error_log
[error]
