# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

repeat_each(2);
plan tests => repeat_each() * blocks() * 3;
no_long_string();
run_tests();

__DATA__

=== TEST 1: empty dictionary
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local d = ngx.shared.dogs
            ngx.say(d:flush_expired_tail(1))
        }
    }
--- request
GET /test
--- response_body
0
--- no_error_log
[error]

=== TEST 2: limit and continuation
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local d = ngx.shared.dogs
            for i = 1, 3 do assert(d:set(i, i, 0.01)) end
            ngx.sleep(0.03)
            ngx.say(d:flush_expired_tail(2))
            ngx.say(d:get_stale(1))
            ngx.say(d:get_stale(2))
            ngx.say(d:get_stale(3))
            ngx.say(d:flush_expired_tail(2))
            ngx.say(d:flush_expired_tail(2))
        }
    }
--- request
GET /test
--- response_body
2
nil
nil
3niltrue
1
0
--- no_error_log
[error]

=== TEST 3: permanent tail blocks expired items
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local d = ngx.shared.dogs
            assert(d:set("blocker", 1))
            assert(d:set("expired", 2, 0.01))
            ngx.sleep(0.03)
            ngx.say(d:flush_expired_tail(10))
            ngx.say(d:flush_expired_tail(10))
            ngx.say(d:flush_expired())
            ngx.say(d:get("blocker"))
        }
    }
--- request
GET /test
--- response_body
0
0
1
1
--- no_error_log
[error]

=== TEST 4: stop after expired prefix at live item
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local d = ngx.shared.dogs
            assert(d:set("old", 1, 0.01))
            assert(d:set("live", 2, 60))
            assert(d:set("new", 3, 0.01))
            ngx.sleep(0.03)
            ngx.say(d:flush_expired_tail(10))
            ngx.say(d:get_stale("old"))
            ngx.say(d:get_stale("new"))
            ngx.say(d:flush_expired(10))
        }
    }
--- request
GET /test
--- response_body
1
nil
3niltrue
1
--- no_error_log
[error]

=== TEST 5: successful access moves blocker away from tail
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local d = ngx.shared.dogs
            assert(d:set("blocker", 1))
            assert(d:set("expired", 2, 0.01))
            assert(d:get("blocker") == 1)
            ngx.sleep(0.03)
            ngx.say(d:flush_expired_tail(10))
            ngx.say(d:get("blocker"))
        }
    }
--- request
GET /test
--- response_body
1
1
--- no_error_log
[error]

=== TEST 6: renewal before cleanup preserves node
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local d = ngx.shared.dogs
            assert(d:set("renewed", 1, 0.01))
            assert(d:set("expired", 2, 0.01))
            ngx.sleep(0.03)
            assert(d:expire("renewed", 60))
            ngx.say(d:flush_expired_tail(10))
            ngx.say(d:get("renewed"))
            ngx.say(d:flush_expired())
        }
    }
--- request
GET /test
--- response_body
0
1
1
--- no_error_log
[error]

=== TEST 7: expired list frees members and counts once
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local d = ngx.shared.dogs
            local before = d:free_space()
            for i = 1, 100 do assert(d:rpush("list", string.rep("x", 1024))) end
            assert(d:expire("list", 0.01))
            assert(d:set("next", 2, 0.01))
            ngx.sleep(0.03)
            ngx.say(d:flush_expired_tail(1))
            ngx.say(d:get_stale("list"))
            ngx.say(d:flush_expired_tail(1))
            ngx.say(d:free_space() == before)
        }
    }
--- request
GET /test
--- response_body
1
nil
1
true
--- no_error_log
[error]

=== TEST 8: surviving LRU order is unchanged
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local d = ngx.shared.dogs
            assert(d:set("first", 1))
            assert(d:set("second", 2))
            assert(d:expire("second", 0.01))
            ngx.say(d:flush_expired_tail(10))
            ngx.sleep(0.03)
            ngx.say(d:flush_expired_tail(10))
            ngx.say(d:flush_expired())
        }
    }
--- request
GET /test
--- response_body
0
0
1
--- no_error_log
[error]

=== TEST 9: invalid limits
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local d = ngx.shared.dogs
            for _, limit in ipairs({0, -1, 0.5, 1.5, 2147483648, math.huge,
                                     -math.huge, 0/0, false, {}, "bad"}) do
                local ok = pcall(d.flush_expired_tail, d, limit)
                ngx.say(ok)
            end
            ngx.say((pcall(d.flush_expired_tail, d)))
            ngx.say((pcall(d.flush_expired_tail, d, 1, 2)))
            ngx.say(d:flush_expired_tail(2147483647))
        }
    }
--- request
GET /test
--- response_body
false
false
false
false
false
false
false
false
false
false
false
false
false
0
--- no_error_log
[error]

=== TEST 10: original flush still scans past live items and honors its limit
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local d = ngx.shared.dogs
            assert(d:set("blocker", 1))
            for i = 1, 3 do assert(d:set(i, i, 0.01)) end
            ngx.sleep(0.03)
            ngx.say(d:flush_expired_tail(10))
            ngx.say(d:flush_expired(1))
            ngx.say(d:flush_expired(0))
            ngx.say(d:flush_expired())
            ngx.say(d:get("blocker"))
        }
    }
--- request
GET /test
--- response_body
0
1
2
0
1
--- no_error_log
[error]
