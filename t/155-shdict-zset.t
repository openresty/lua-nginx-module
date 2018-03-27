# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 0);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: zset & zget & zrem
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:zset("foo", "bar", "hello")
            if len then
                ngx.say("zset ", len)
            else
                ngx.say("szet err: ", err)
            end

            local len, err = dogs:zset("foo", "foo", 999)
            if len then
                ngx.say("zset ", len)
            else
                ngx.say("szet err: ", err)
            end

            local zkey, val = dogs:zget("foo", "bar")
            ngx.say(zkey, " ", val)

            local zkey, val = dogs:zget("foo", "foo")
            ngx.say(zkey, " ", val)

            local val, err = dogs:zrem("foo", "bar")
            if val then
              ngx.say(val)
            else
              ngx.say("zrem err: ", err)
            end

            local val, err = dogs:zrem("foo", "foo")
            if val then
              ngx.say(val)
            else
              ngx.say("zrem err: ", err)
            end

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
zset 1
zset 2
bar hello
foo 999
hello
999
--- no_error_log
[error]


=== TEST 2: exptime
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:zset("foo", "bar", "hello", 1)
            if len then
                ngx.say("zset ", len)
            else
                ngx.say("zset err: ", err)
            end

            local zkey, val = dogs:zget("foo", "bar")
            ngx.say(zkey, " ", val)

            ngx.sleep(2)
            
            local zkey, val = dogs:zget("foo", "bar")
            ngx.say(zkey)

            local len, err = dogs:zset("foo", "bar", "hello2")
            if len then
                ngx.say("zset ", len)
            else
                ngx.say("zset err: ", err)
            end

            local zkey, val = dogs:zget("foo", "bar")
            ngx.say(zkey, " ", val)

            local val, err = dogs:zrem("foo", "bar")
            if val then
              ngx.say(val)
            else
              ngx.say("zrem err: ", err)
            end

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
zset 1
bar hello
nil
zset 1
bar hello2
hello2
--- no_error_log
[error]


=== TEST 3: zset & zgetall
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local vals = {
              { "a", 1 }, { "b", 2 }, { "c", 3 }, { "d", 4 }, { "e", 5 }
            }

            for _,v in ipairs(vals) do
               local len, err = dogs:zset("foo", unpack(v))
               if not len then
                   ngx.say("zset err: ", err)
               end
            end

            ngx.say(dogs:zcard("foo"))

            local v = dogs:zgetall("foo")
            for _,i in ipairs(v) do
              ngx.say(unpack(i))
            end
  
            for _,i in pairs(vals) do
               local zkey = unpack(i) 
               ngx.print(dogs:zrem("foo", zkey))
            end
            ngx.say()
            ngx.say(dogs:zcard("foo"))

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
5
a1
b2
c3
d4
e5
12345
nil
--- no_error_log
[error]


=== TEST 4: zset & zscan
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local vals = {
              { "a", 1 }, { "b", 2 }, { "c", 3 }, { "d", 4 }, { "e", 5 }
            }

            for _,v in ipairs(vals) do
               local len, err = dogs:zset("foo", unpack(v))
               if not len then
                   ngx.say("zset err: ", err)
               end
            end

            ngx.say(dogs:zcard("foo"))

            dogs:zscan("foo", function(k,v)
              ngx.say(k, v)
            end)

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
5
a1
b2
c3
d4
e5
--- no_error_log
[error]


=== TEST 5: zset & zscan (range)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local vals = {
              { "a", 1 },
              { "aa", 11 },
              { "b", 2 },
              { "bb", 22 },
              { "aaa", 111 },
              { "aab", 112 },
              { "x", 0 }
            }

            for _,v in ipairs(vals) do
               local len, err = dogs:zset("foo", unpack(v))
               if not len then
                   ngx.say("zset err: ", err)
               end
            end

            ngx.say(dogs:zcard("foo"))

            dogs:zscan("foo", function(k,v)
              if k:sub(1,2) ~= "aa" then
                return true
              end
              ngx.say(k, v)
            end, "aa")

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
7
aa11
aaa111
aab112
--- no_error_log
[error]
