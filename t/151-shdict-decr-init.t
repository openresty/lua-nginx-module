# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

no_long_string();

run_tests();

__DATA__

=== TEST 1: decr key with init (key exists)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local res, err = dogs:decr("foo", 17, 1)
            ngx.say("decr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
decr: 15 nil
foo = 15
--- no_error_log
[error]



=== TEST 2: decr key with init (key not exists)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:flush_all()
            dogs:set("bah", 32)
            local res, err = dogs:decr("foo", 1, 10502)
            ngx.say("decr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
decr: 10501 nil
foo = 10501
--- no_error_log
[error]



=== TEST 3: decr key with init (key expired and size not matched)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            for i = 1, 20 do
                dogs:set("bar" .. i, i, 0.001)
            end
            dogs:set("foo", "32", 0.001)
            ngx.sleep(0.002)
            local res, err = dogs:decr("foo", 1, 10502)
            ngx.say("decr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
decr: 10501 nil
foo = 10501
--- no_error_log
[error]



=== TEST 4: decr key with init (key expired and size matched)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            for i = 1, 20 do
                dogs:set("bar" .. i, i, 0.001)
            end
            dogs:set("foo", 32, 0.001)
            ngx.sleep(0.002)
            local res, err = dogs:decr("foo", 1, 10502)
            ngx.say("decr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
decr: 10501 nil
foo = 10501
--- no_error_log
[error]



=== TEST 5: decr key with init (forcibly override other valid entries)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:flush_all()
            local long_prefix = string.rep("1234567890", 100)
            for i = 1, 1000 do
                local success, err, forcible = dogs:set(long_prefix .. i, i)
                if forcible then
                    dogs:delete(long_prefix .. i)
                    break
                end
            end
            local res, err, forcible = dogs:decr(long_prefix .. "bar", 1, 10502)
            ngx.say("decr: ", res, " ", err, " ", forcible)
            local res, err, forcible = dogs:decr(long_prefix .. "foo", 1, 10502)
            ngx.say("decr: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get(long_prefix .. "foo"))
        }
    }
--- request
GET /test
--- response_body
decr: 10501 nil false
decr: 10501 nil true
foo = 10501
--- no_error_log
[error]



=== TEST 6: decr key without init (no forcible returned)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 1)
            local res, err, forcible = dogs:decr("foo", 1)
            ngx.say("decr: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
decr: 0 nil nil
foo = 0
--- no_error_log
[error]



=== TEST 7: decr key (original value is not number)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", true)
            local res, err = dogs:decr("foo", 1, 0)
            ngx.say("decr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
decr: nil not a number
foo = true
--- no_error_log
[error]



=== TEST 8: init is not number
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local res, err, forcible = dogs:decr("foo", 1, "bar")
            ngx.say("decr: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- error_code: 500
--- response_body_like: 500 Internal Server Error
--- error_log
number expected, got string



=== TEST 9: init below 0
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local res, err = dogs:decr("foo", 2, 1)
            ngx.say("decr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
decr: nil cannot initialize decr below zero
foo = nil
--- no_error_log
[error]
