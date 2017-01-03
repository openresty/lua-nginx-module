# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket 'no_plan';
use Test::Nginx::Socket::Lua;


#log_level("warn");
no_long_string();

run_tests();

__DATA__

=== TEST 1: simple exit_worker_by_lua_block
--- http_config
    exit_worker_by_lua_block {
        ngx.log(ngx.NOTICE, "log from exit_worker_by_lua_block")
        -- grep_error_log chop
        -- log from exit_worker_by_lua_block
        -- --- grep_error_log_out eval
        -- ["log from exit_worker_by_lua_block\n", ""]
        -- Due to the use grep_error_log and grep_error_log_out is invalid, So use grep verification test(exit_worker_by_lua* run when worker exit)
        -- grep "log from exit_worker_by_lua_block" t/servroot/logs/error.log
    }
--- config
    location /t {
        echo "ok";
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 1: simple exit_worker_by_lua_file
--- http_config
    exit_worker_by_lua_file html/exit_worker.lua;
    # grep_error_log chop
    # log from exit_worker_by_lua_file
    # --- grep_error_log_out eval
    # ["log from exit_worker_by_lua_file\n", ""]
    # Due to the use grep_error_log and grep_error_log_out is invalid, So use grep verification test(exit_worker_by_lua* run when worker exit)
    # grep "log from exit_worker_by_lua_file" t/servroot/logs/error.log
--- config
    location /t {
        echo "ok";
    }
--- user_files
>>> exit_worker.lua
ngx.log(ngx.NOTICE, "log from exit_worker_by_lua_file")
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]

