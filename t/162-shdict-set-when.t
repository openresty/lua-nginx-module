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

=== TEST 1: set_when success
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            dogs:set_when("foo", 32, 33)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
33 number
--- no_error_log
[error]



=== TEST 2: set_when fail
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local ok, err, forcible = dogs:set_when("foo", 32, 33)
            ngx.say(ok, " ", err, " ", forcible)
            local ok, err, forcible = dogs:set_when("foo", 32, 34)
            ngx.say(ok, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
true nil false
false already modified false
33 number
--- no_error_log
[error]



=== TEST 3: set_when success for expired value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0.01)
            ngx.sleep(0.02)
            local ok, err, forcible = dogs:set_when("foo", 32, 33)
            ngx.say(ok, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
true nil false
33 number
--- no_error_log
[error]



=== TEST 4: set_when success for unmatched expired value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0.01)
            ngx.sleep(0.02)
            local ok, err, forcible = dogs:set_when("foo", 31, 33)
            ngx.say(ok, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
true nil false
33 number
--- no_error_log
[error]



=== TEST 5: set_when success when old_value did not exist
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local ok, err, forcible = dogs:set_when("foo", 32, 33)
            ngx.say(ok, " ", err, " ", forcible)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
true nil false
33 number
--- no_error_log
[error]
