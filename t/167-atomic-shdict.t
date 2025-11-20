# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

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
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local ok, err = dogs:cas("foo", 32, nil, 42)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val), " ", ok)
        }
    }
--- request
GET /test
--- response_body
42 number true
--- no_error_log
[error]



=== TEST 2: CAS int value failed
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local ok, err = dogs:cas("foo", 31, nil, 42)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val), " ", ok, " ", err)
        }
    }
--- request
GET /test
--- response_body
32 number false false
--- no_error_log
[error]



=== TEST 3: CAS string value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local value = "Turboencabulator"
            dogs:set("foo", value)
            dogs:cas("foo", value, nil, "bar")
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        }
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
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local value = "Turboencabulator"
            dogs:set("foo", value)
            local ok, err = dogs:cas("foo", "c", nil, "bar")
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val), " ", ok, " ", err)
        }
    }
--- request
GET /test
--- response_body
Turboencabulator string false false
--- no_error_log
[error]



=== TEST 5: CAS boolean value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", true)
            dogs:cas("foo", true, nil, false)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
        }
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
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar", nil, 42)
            local ok, err = dogs:cas("foo", nil, 42, "baz")
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val), " ", ok, " ", err)
        }
    }
--- request
GET /test
--- response_body
baz string true nil
--- no_error_log
[error]



=== TEST 7: CAS flags invalid
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar", nil, 42)
            local ok, err = dogs:cas("foo", nil, 41, "baz")
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val), " ", ok, " ", err)
        }
    }
--- request
GET /test
--- response_body
bar string false false
--- no_error_log
[error]



=== TEST 8: CAS invalid flags error message
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar", nil, 42)
            local ok, err = dogs:cas("foo", nil, 41, "baz")
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val), " ", ok, " ", err )

        }
    }
--- request
GET /test
--- response_body
bar string false false
--- no_error_log
[error]



=== TEST 9: CAS invalid value error message
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar", nil, 42)
            local ok, err = dogs:cas("foo", "baz", nil, "bas")

            local val = dogs:get("foo")
            ngx.say(val, " ", type(val), " ", ok, " ", err)
        }
    }
--- request
GET /test
--- response_body
bar string false false
--- no_error_log
[error]



=== TEST 10: COG number value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local val = dogs:get_if_not_eq("foo", 31)
            ngx.say(val, " ", type(val))
        }
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
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local val, err = dogs:get_if_not_eq("foo", 32)
            ngx.say(val, " ", type(val)," ", err)
        }
    }
--- request
GET /test
--- response_body
nil nil false
--- no_error_log
[error]



=== TEST 12: COG string value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar")
            local val, err = dogs:get_if_not_eq("foo", "baz")
            ngx.say(val, " ", type(val))
        }
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
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", "bar")
            local val, err = dogs:get_if_not_eq("foo", "bar")
            ngx.say(val, " ", type(val)," ", err)
        }
    }
--- request
GET /test
--- response_body
nil nil false
--- no_error_log
[error]



=== TEST 14: COG boolean value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", true)
            local val, err = dogs:get_if_not_eq("foo", false)
            ngx.say(val, " ", type(val))
        }
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
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", true)
            local val, err = dogs:get_if_not_eq("foo", true)
            ngx.say(val, " ", type(val)," ", err)
        }
    }
--- request
GET /test
--- response_body
nil nil false
--- no_error_log
[error]



=== TEST 16: COG flags
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 42)
            local val, err = dogs:get_if_not_eq("foo", nil, 41)
            ngx.say(val, " ", type(val))
        }
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
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, nil, 42)
            local val, err = dogs:get_if_not_eq("foo", nil, 42)
            ngx.say(val, " ", type(val)," ", err)
        }
    }
--- request
GET /test
--- response_body
nil nil false
--- no_error_log
[error]



=== TEST 18: COG flags 0
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, nil, 1)
            local val = dogs:get_if_not_eq("foo", nil, 0)
            ngx.say(val, " ", type(val))
        }
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
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local val, err = dogs:get_if_not_eq("foo", nil, 0)
            ngx.say(val, " ", type(val)," ", err)
        }
    }
--- request
GET /test
--- response_body
nil nil false
--- no_error_log
[error]



=== TEST 20: COG flags match but not value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local val, err = dogs:get_if_not_eq("foo", 31, 0)
            ngx.say(val, " ", type(val))
        }
    }
--- request
GET /test
--- response_body
32 number
--- no_error_log
[error]



=== TEST 21: COG value match but not flags
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0, 10)
            local val = dogs:get_if_not_eq("foo", 32, 11)
            ngx.say(val, " ", type(val))
        }
    }
--- request
GET /test
--- response_body
32 number
--- no_error_log
[error]



=== TEST 22: COG flags and value match
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0, 10)
            local val, err = dogs:get_if_not_eq("foo", 32, 10)
            ngx.say(val, " ", type(val)," ", err)
        }
    }
--- request
GET /test
--- response_body
nil nil false
--- no_error_log
[error]



=== TEST 23: CAS only value match
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0, 10)
            local ok, err = dogs:cas("foo", 32, 11, 1, 1)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val)," ", ok, " ", err)
        }
    }
--- request
GET /test
--- response_body
32 number false false
--- no_error_log
[error]



=== TEST 24: CAS only flags match
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0, 10)
            local ok, err = dogs:cas("foo", 31, 10, 1, 1)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val)," ", ok, " ", err)
        }
    }
--- request
GET /test
--- response_body
32 number false false
--- no_error_log
[error]



=== TEST 25: CAS set nil
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0, 10)
            local ok, err = dogs:cas("foo", 32, 10)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val)," ", ok)
        }
    }
--- request
GET /test
--- response_body
nil nil true
--- no_error_log
[error]



=== TEST 26: CAS as remove
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0, 10)
            local ok, err = dogs:cas("foo")
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val)," ", ok)
        }
    }
--- request
GET /test
--- response_body
nil nil true
--- no_error_log
[error]



=== TEST 27: CAS as set value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0, 10)
            local ok, err = dogs:cas("foo", nil, nil, "foo")
            local val, flags = dogs:get("foo")
            ngx.say(val, " ", type(val)," ", flags, " ", ok)
        }
    }
--- request
GET /test
--- response_body
foo string 10 true
--- no_error_log
[error]



=== TEST 28: CAS as set flag
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0, 10)
            local ok, err = dogs:cas("foo", nil, nil, nil, 13)
            local val, flags = dogs:get("foo")
            ngx.say(val, " ", type(val), " ", flags, " ", ok)
        }
    }
--- request
GET /test
--- response_body
32 number 13 true
--- no_error_log
[error]



=== TEST 29: COG as get
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0, 10)
            local val, flags = dogs:get_if_not_eq("foo")
            ngx.say(val, " ", type(val), " ", flags )
        }
    }
--- request
GET /test
--- response_body
32 number 10
--- no_error_log
[error]



=== TEST 30: COG get nothing
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local val, flags = dogs:get_if_not_eq("foo")
            ngx.say(val, " ", type(val), " ", flags )
        }
    }
--- request
GET /test
--- response_body
nil nil nil
--- no_error_log
[error]
