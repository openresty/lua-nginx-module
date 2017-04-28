# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 8);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: delay init_by_lua by only fake_delay_init_lua
--- http_config
    lua_fake_delay_shm x1 1m;
    lua_fake_delay_shm x2 2m;
    init_by_lua_block {
        local shm_zones = require("fake_delay_init_lua")
        local name, size

        local x1 = shm_zones.x1
        name, size = x1:get_info()
        ngx.log(ngx.ERR, type(x1))
        ngx.log(ngx.ERR, "name=", name)
        ngx.log(ngx.ERR, "size=", size)

        local x2 = shm_zones.x2
        name, size = x2:get_info()
        ngx.log(ngx.ERR, type(x1))
        ngx.log(ngx.ERR, "name=", name)
        ngx.log(ngx.ERR, "size=", size)
    }
--- config
    location = /test {
        content_by_lua_block {
            ngx.say("hello")
        }
    }
--- request
GET /test
--- response_body
hello
--- error_log
table
name=x1
size=1048576
table
name=x2
size=2097152



=== TEST 2: delay by lua_shared_dict and fake_delay_init_lua
--- http_config
    lua_fake_delay_shm x1 1m;
    lua_fake_delay_shm x2 2m;

    lua_shared_dict dogs 1m;

    init_by_lua_block {
        local shm_zones = require("fake_delay_init_lua")
        local name, size

        local x1 = shm_zones.x1
        name, size = x1:get_info()
        ngx.log(ngx.ERR, type(x1))
        ngx.log(ngx.ERR, "name=", name)
        ngx.log(ngx.ERR, "size=", size)

        local x2 = shm_zones.x2
        name, size = x2:get_info()
        ngx.log(ngx.ERR, type(x1))
        ngx.log(ngx.ERR, "name=", name)
        ngx.log(ngx.ERR, "size=", size)

        local dogs = ngx.shared.dogs
        dogs:set("foo", "hello, FOO")
    }
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local foo = dogs:get("foo")
            ngx.say(foo)
        }
    }
--- request
GET /test
--- response_body
hello, FOO
--- error_log
table
name=x1
size=1048576
table
name=x2
size=2097152
