# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 0);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: lpush & lpop
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local val, err = dogs:llen("foo")
            ngx.say(val, " ", err)

            local val, err = dogs:lpop("foo")
            ngx.say(val, " ", err)

            local val, err = dogs:llen("foo")
            ngx.say(val, " ", err)

            local val, err = dogs:lpop("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
1 nil
bar nil
0 nil
nil nil
--- no_error_log
[error]



=== TEST 2: get operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
nil value is a list
--- no_error_log
[error]



=== TEST 3: set operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:set("foo", "bar")
            ngx.say(ok, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
true nil
bar nil
--- no_error_log
[error]



=== TEST 4: replace operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:replace("foo", "bar")
            ngx.say(ok, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
true nil
bar nil
--- no_error_log
[error]



=== TEST 5: add operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:add("foo", "bar")
            ngx.say(ok, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
false exists
nil value is a list
--- no_error_log
[error]



=== TEST 6: delete operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:delete("foo")
            ngx.say(ok, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
true nil
nil nil
--- no_error_log
[error]



=== TEST 7: incr operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:incr("foo", 1)
            ngx.say(ok, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
nil not a number
nil value is a list
--- no_error_log
[error]



=== TEST 8: get_keys operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local keys, err = dogs:get_keys()
            ngx.say("key: ", keys[1])
        }
    }
--- request
GET /test
--- response_body
push success
key: foo
--- no_error_log
[error]



=== TEST 9: push operation on key-value type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local ok, err = dogs:set("foo", "bar")
            if ok then
                ngx.say("set success")
            else
                ngx.say("set err: ", err)
            end

            local len, err = dogs:lpush("foo", "bar")
            ngx.say(len, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
set success
nil value not a list
bar nil
--- no_error_log
[error]



=== TEST 10: pop operation on key-value type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local ok, err = dogs:set("foo", "bar")
            if ok then
                ngx.say("set success")
            else
                ngx.say("set err: ", err)
            end

            local val, err = dogs:lpop("foo")
            ngx.say(val, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
set success
nil value not a list
bar nil
--- no_error_log
[error]



=== TEST 11: llen operation on key-value type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local ok, err = dogs:set("foo", "bar")
            if ok then
                ngx.say("set success")
            else
                ngx.say("set err: ", err)
            end

            local val, err = dogs:llen("foo")
            ngx.say(val, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
set success
nil value not a list
bar nil
--- no_error_log
[error]



=== TEST 12: lpush and lpop
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            for i = 1, 3 do
                local len, err = dogs:lpush("foo", i)
                if len ~= i then
                    ngx.say("push err: ", err)
                    break
                end
            end

            for i = 1, 3 do
                local val, err = dogs:lpop("foo")
                if not val then
                    ngx.say("pop err: ", err)
                    break
                else
                    ngx.say(val)
                end
            end
        }
    }
--- request
GET /test
--- response_body
3
2
1
--- no_error_log
[error]



=== TEST 13: lpush and rpop
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            for i = 1, 3 do
                local len, err = dogs:lpush("foo", i)
                if len ~= i then
                    ngx.say("push err: ", err)
                    break
                end
            end

            for i = 1, 3 do
                local val, err = dogs:rpop("foo")
                if not val then
                    ngx.say("pop err: ", err)
                    break
                else
                    ngx.say(val)
                end
            end
        }
    }
--- request
GET /test
--- response_body
1
2
3
--- no_error_log
[error]



=== TEST 14: rpush and lpop
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            for i = 1, 3 do
                local len, err = dogs:rpush("foo", i)
                if len ~= i then
                    ngx.say("push err: ", err)
                    break
                end
            end

            for i = 1, 3 do
                local val, err = dogs:lpop("foo")
                if not val then
                    ngx.say("pop err: ", err)
                    break
                else
                    ngx.say(val)
                end
            end
        }
    }
--- request
GET /test
--- response_body
1
2
3
--- no_error_log
[error]



=== TEST 15: list removed: expired
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local max
            for i = 1, 10000 do
                local key = string.format("%05d", i)

                local len , err = dogs:lpush(key, i)
                if not len then
                    max = i
                    break
                end

                local ok = dogs:expire(key, 0.01)
                if not ok then
                    ngx.say("expire error")
                end
            end

            local keys = dogs:get_keys(0)

            ngx.say("max-1 matched keys length: ", max-1 == #keys)

            ngx.sleep(0.01)

            local keys = dogs:get_keys(0)

            ngx.say("keys all expired, left number: ", #keys)

            -- some reused, some removed
            for i = 10000, 1, -1 do
                local key = string.format("%05d", i)

                local len, err = dogs:lpush(key, i)
                if not len then
                    ngx.say("loop again, max matched: ", 10001-i == max)
                    break
                end
            end

            dogs:flush_all()

            dogs:flush_expired()

            for i = 1, 10000 do
                local key = string.format("%05d", i)

                local len, err = dogs:lpush(key, i)
                if not len then
                    ngx.say("loop again, max matched: ", i == max)
                    break
                end
            end
        }
    }
--- request
GET /test
--- response_body
max-1 matched keys length: true
keys all expired, left number: 0
loop again, max matched: true
loop again, max matched: true
--- no_error_log
[error]



=== TEST 16: list removed: forcibly
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local max
            for i = 1, 20000 do
                local ok, err, forcible  = dogs:set(i, i)
                if not ok or forcible then
                    max = i
                    break
                end
            end

            local two = dogs:get(2)

            ngx.say("two == number 2: ", two == 2)

            dogs:flush_all()
            dogs:flush_expired()

            local keys = dogs:get_keys(0)

            ngx.say("no one left: ", #keys)

            for i = 1, 20000 do
                local key = string.format("%05d", i)

                local len, err = dogs:lpush(key, i)
                if not len then
                    break
                end
            end

            for i = 1, max do
                local ok, err = dogs:set(i, i)
                if not ok then
                    ngx.say("set err: ", err)
                    break
                end
            end

            local two = dogs:get(2)

            ngx.say("two == number 2: ", two == 2)
        }
    }
--- request
GET /test
--- response_body
two == number 2: true
no one left: 0
two == number 2: true
--- no_error_log
[error]



=== TEST 16: expire on all types
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("list", "foo")
            if not len then
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:set("key", "bar")
            if not ok then
                ngx.say("set err: ", err)
            end

            local keys = dogs:get_keys(0)

            ngx.say("keys number: ", #keys)

            for i = 1, #keys do
                local ok, err = dogs:expire(keys[i], 0.01)
                if not ok then
                    ngx.say("expire err: ", err)
                end
            end

            local ok, err = dogs:expire("not-exits", 1)
            if not ok then
                ngx.say("expire on not-exists, err: ", err)
            end

            ngx.sleep(0.01)

            local keys = dogs:get_keys(0)

            ngx.say("keys number: ", #keys)
        }
    }
--- request
GET /test
--- response_body
keys number: 2
expire on not-exists, err: not found
keys number: 0
--- no_error_log
[error]



=== TEST 17: long list node
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local long_str = string.rep("foo", 10)

            for i = 1, 3 do
                local len, err = dogs:lpush("list", long_str)
                if not len then
                    ngx.say("push err: ", err)
                end
            end

            for i = 1, 3 do
                local val, err = dogs:lpop("list")
                if val then
                    ngx.say(val)
                end
            end
        }
    }
--- request
GET /test
--- response_body
foofoofoofoofoofoofoofoofoofoo
foofoofoofoofoofoofoofoofoofoo
foofoofoofoofoofoofoofoofoofoo
--- no_error_log
[error]
