# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => repeat_each() * (blocks() * 1 + 4);

#log_level("warn");
no_long_string();

run_tests();

__DATA__

=== TEST 1: simple exit_worker_by_lua_block
--- http_config
    exit_worker_by_lua_block {
        ngx.log(ngx.NOTICE, "log from exit_worker_by_lua_block")
    }
--- config
    location /t {
        echo "ok";
    }
--- request
GET /t
--- response_body
ok
--- stop_after_request
--- error_log
log from exit_worker_by_lua_block



=== TEST 2: simple exit_worker_by_lua_file
--- http_config
    exit_worker_by_lua_file html/exit_worker.lua;
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
--- stop_after_request
--- error_log
log from exit_worker_by_lua_file

