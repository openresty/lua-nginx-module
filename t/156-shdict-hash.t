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

=== TEST 1: hset & hget & hdel
--- http_config
    lua_shared_dict test 1m;
--- config
    location = /test {
        content_by_lua_block {
            local shm = ngx.shared.test

            local len, err = shm:hset("a", "a1", "a1")
            if len then
                ngx.say("hset ", len)
            else
                ngx.say("hset err: ", err)
            end

            local len, err = shm:hset("a", "a2", 222)
            if len then
                ngx.say("hset ", len)
            else
                ngx.say("hset err: ", err)
            end

            local val = shm:hget("a", "a1")
            ngx.say(val)

            local zkey, val = shm:hget("a", "a2")
            ngx.say(val)

            shm:hdel("a")
        }
    }
--- request
GET /test
--- response_body
hset 1
hset 2
a1
nil
--- no_error_log
[error]


=== TEST 2: exptime
--- http_config
    lua_shared_dict test 1m;
--- config
    location = /test {
        content_by_lua_block {
            local shm = ngx.shared.test

            local len, err = shm:hset("a", "a1", "a1", 1)
            if len then
                ngx.say("hset ", len)
            else
                ngx.say("hset err: ", err)
            end

            local val = shm:hget("a", "a1")
            ngx.say(val)

            ngx.sleep(2)
            
            local val = shm:hget("a", "a1")
            ngx.say(val)

            local len, err = shm:hset("a", "a1", "a11")
            if len then
                ngx.say("hset ", len)
            else
                ngx.say("hset err: ", err)
            end

            local val = shm:hget("a", "a1")
            ngx.say(val)

            shm:hdel("a")
        }
    }
--- request
GET /test
--- response_body
hset 1
a1
nil
hset 1
a11
--- no_error_log
[error]
