# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

#log_level("warn");
no_long_string();
our $HtmlDir = html_dir;

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
--- shutdown_error_log
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
--- shutdown_error_log
log from exit_worker_by_lua_file



=== TEST 3: exit_worker_by_lua (require a global table)
--- http_config eval
    qq{lua_package_path '$::HtmlDir/?.lua;;';
        exit_worker_by_lua_block {
            foo = require("foo")
            ngx.log(ngx.NOTICE, foo.bar)
        }}
--- config
    location /t {
        content_by_lua_block {
            foo = require("foo")
            foo.bar = "hello, world"
            ngx.say("ok")
        }
    }
--- user_files
>>> foo.lua
return {}
--- request
GET /t
--- response_body
ok
--- shutdown_error_log
hello, world



=== TEST 4: exit_worker_by_lua single process ngx.timer not work
--- http_config
    exit_worker_by_lua_block {
        local function bar()
            ngx.log(ngx.ERR, "run the timer!"
        end

        local ok, err = ngx.timer.at(0, bar)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: " .. err)
        else
            ngx.log(ngx.NOTICE, "success")
        end
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



=== TEST 4: exit_worker_by_lua use shdict
--- http_config
    lua_shared_dict dog 10m;
    exit_worker_by_lua_block {
        local dog = ngx.shared.dog
        local val, err = dog:get("foo")
        if not val then
            ngx.log(ngx.ERR, "failed get shdict: " .. err)
        else
            ngx.log(ngx.NOTICE, "get val: " .. val)
        end
    }
--- config
    location /t {
        content_by_lua_block {
            local dog = ngx.shared.dog
            dog:set("foo", 100)
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- shutdown_error_log
get 11val: 1000

