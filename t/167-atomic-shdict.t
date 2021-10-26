# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: CAS int value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            dogs:cas("foo", 42, nil, nil, 32)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
42 number
--- no_error_log
[error]



=== TEST 2: CAS int value faild
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            dogs:cas("foo", 42, nil, nil, 31)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
32 number
--- no_error_log
[error]




=== TEST 3: CAS string value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local value = "Turboencabulator"
            dogs:set("foo", value)
            dogs:cas("foo", "bar", nil, nil, value)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
bar string
--- no_error_log
[error]



=== TEST 4: CAS string value invalid
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local value = "Turboencabulator"
            dogs:set("foo", value)
            dogs:cas("foo", "bar", nil, nil, "c")
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
Turboencabulator string
--- no_error_log
[error]



=== TEST 5: CAS boolean value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", true)
            dogs:cas("foo", false, nil, nil, true)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
false boolean
--- no_error_log
[error]



=== TEST 6: CAS flags
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar", nil, 42)
            dogs:cas("foo", "baz", nil, nil, nil, 42)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
baz string
--- no_error_log
[error]



=== TEST 7: CAS flags invalid
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar", nil, 42)
            dogs:cas("foo", "baz", nil, nil, nil, 41)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
bar string
--- no_error_log
[error]



=== TEST 8: CAS invalid flags error message
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar", nil, 42)
            local ok, err = dogs:cas("foo", "baz", nil, nil, nil, 41)
            if not ok then
                ngx.say(err)
            end
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
old flags does not match
bar string
--- no_error_log
[error]



=== TEST 9: CAS invalid value error message
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar", nil, 42)
            local ok, err = dogs:cas("foo", "baz", nil, nil, "ba", nil)
            if not ok then
                ngx.say(err)
            end
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
old value does not match
bar string
--- no_error_log
[error]



=== TEST 10: COG number value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local val = dogs:cog("foo", 31)
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
32 number
--- no_error_log
[error]



=== TEST 11: COG number value match
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local val, err = dogs:cog("foo", 32)
            ngx.say(val, " ", type(val)," ", err)
        ';
    }
--- request
GET /test
--- response_body
nil nil old value match
--- no_error_log
[error]



=== TEST 12: COG string value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar")
            local val, err = dogs:cog("foo", "baz")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
bar string
--- no_error_log
[error]



=== TEST 13: COG string value match
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar")
            local val, err = dogs:cog("foo", "bar")
            ngx.say(val, " ", type(val)," ", err)
        ';
    }
--- request
GET /test
--- response_body
nil nil old value match
--- no_error_log
[error]



=== TEST 14: COG boolean value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", true)
            local val, err = dogs:cog("foo", false)
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
true boolean
--- no_error_log
[error]



=== TEST 15: COG boolean value match
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", true)
            local val, err = dogs:cog("foo", true)
            ngx.say(val, " ", type(val)," ", err)
        ';
    }
--- request
GET /test
--- response_body
nil nil old value match
--- no_error_log
[error]



=== TEST 16: COG flags
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 42)
            local val, err = dogs:cog("foo", nil, 41)
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
32 number
--- no_error_log
[error]



=== TEST 17: COG flags match
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, nil, 42)
            local val, err = dogs:cog("foo", nil, 42)
            ngx.say(val, " ", type(val)," ", err)
        ';
    }
--- request
GET /test
--- response_body
nil nil old flags match
--- no_error_log
[error]



=== TEST 18: COG flags 0
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, nil, 1)
            local val = dogs:cog("foo", nil, 0)
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
32 number
--- no_error_log
[error]



=== TEST 19: COG flags 0 match
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local val, err = dogs:cog("foo", nil, 0)
            ngx.say(val, " ", type(val)," ", err)
        ';
    }
--- request
GET /test
--- response_body
nil nil old flags match
--- no_error_log
[error]



