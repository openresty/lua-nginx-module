# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua 'no_plan';

run_tests();

__DATA__

=== TEST 1: flag eq
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0, 1)
            local val = dogs:get("Bernese", 1)
            ngx.say(val, " ", type(val))
        }
    }
--- request
GET /test
--- response_body
nil nil
--- no_error_log
[error]



=== TEST 2: fleq neq
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0, 1)
            local val = dogs:get("Bernese", 2)
            ngx.say(val, " " , type(val))
        }
    }
--- request
GET /test
--- response_body
42 number
--- no_error_log
[error]



=== TEST 3: set with no flag
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0)
            local val = dogs:get("Bernese", 2)
            ngx.say(val, " " , type(val))
        }
    }
--- request
GET /test
--- response_body
42 number
--- no_error_log
[error]



=== TEST 4: get with no flag
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0, 1)
            local val = dogs:get("Bernese")
            ngx.say(val, " " , type(val))
        }
    }
--- request
GET /test
--- response_body
42 number
--- no_error_log
[error]



=== TEST 5: set and get with no flag
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0)
            local val = dogs:get("Bernese")
            ngx.say(val, " " , type(val))
        }
    }
--- request
GET /test
--- response_body
42 number
--- no_error_log
[error]



=== TEST 6: set no flag, and read with 0 flag
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42)
            local val = dogs:get("Bernese", 0)
            ngx.say(val, " " , type(val))
        }
    }
--- request
GET /test
--- response_body
nil nil
--- no_error_log
[error]


=== TEST 7: flags_match is true
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0, 1)
            local val, err, flags_match = dogs:get("Bernese", 1)

            ngx.say(val, " ", type(val), " : ",
                    err, " ", type(err), " : ",
                    flags_match, " ", type(flags_match))
        }
    }
--- request
GET /test
--- response_body
nil nil : nil nil : true boolean
--- no_error_log
[error]



=== TEST 8: flags_match is nil
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local val, err, flags_match = dogs:get("Bernese", 3)
            ngx.say(flags_match, " ", type(flags_match))
        }
    }
--- request
GET /test
--- response_body
nil nil
--- no_error_log
[error]



=== TEST 9: get when flag is not number
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0, 1)
            local val = dogs:get("Bernese", {})
        }
    }
--- request
GET /test
--- request_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
cannot convert 'table' to 'int'


=== TEST 10: flag eq stale
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0.01, 1)
            ngx.sleep(0.02)
            local val = dogs:get_stale("Bernese", 1)
            ngx.say(val, " ", type(val))
        }
    }
--- request
GET /test
--- response_body
nil nil
--- no_error_log
[error]



=== TEST 11: fleq neq stale
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0.01, 1)
            ngx.sleep(0.02)
            local val = dogs:get_stale("Bernese", 2)
            ngx.say(val, " " , type(val))
        }
    }
--- request
GET /test
--- response_body
42 number
--- no_error_log
[error]



=== TEST 12: get_stale with no flag
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0.01, 1)
            ngx.sleep(0.02)
            local val = dogs:get_stale("Bernese")
            ngx.say(val, " " , type(val))
        }
    }
--- request
GET /test
--- response_body
42 number
--- no_error_log
[error]



=== TEST 13: flags_match is true
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0.01, 1)
            ngx.sleep(0.02)
            local val, err, stale, flags_match = dogs:get_stale("Bernese", 1)

            ngx.say(val, " ", type(val), " : ",
                    err, " ", type(err), " : ",
                    flags_match, " ", type(flags_match))
        }
    }
--- request
GET /test
--- response_body
nil nil : nil nil : true boolean
--- no_error_log
[error]



=== TEST 14: flags_match is nil
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local val, err, stale, flags_match = dogs:get_stale("Bernese", 3)
            ngx.say(flags_match, " ", type(flags_match))
        }
    }
--- request
GET /test
--- response_body
nil nil
--- no_error_log
[error]



=== TEST 15: get when flag is not number
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("Bernese", 42, 0, 1)
            local val = dogs:get_stale("Bernese", {})
        }
    }
--- request
GET /test
--- request_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
cannot convert 'table' to 'int'
