# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 2);

#no_diff();
#no_long_string();
#master_on();
#workers(2);
run_tests();

__DATA__

=== TEST 1: string key, int value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            dogs:set("bah", 10502)
            ngx.say(dogs:get("foo"))
            ngx.say(dogs:get("bah"))
        ';
    }
--- request
GET /test
--- response_body
32
10502



=== TEST 2: string key, floating-point value
--- http_config
    lua_shared_dict cats 1m;
--- config
    location = /test {
        content_by_lua '
            local cats = ngx.shared.cats
            cats:set("foo", 3.14159)
            cats:set("baz", 1.28)
            cats:set("baz", 3.96)
            ngx.say(cats:get("foo"))
            ngx.say(cats:get("baz"))
        ';
    }
--- request
GET /test
--- response_body
3.14159
3.96



=== TEST 3: string key, boolean value
--- http_config
    lua_shared_dict cats 1m;
--- config
    location = /test {
        content_by_lua '
            local cats = ngx.shared.cats
            cats:set("foo", true)
            cats:set("bar", false)
            ngx.say(cats:get("foo"))
            ngx.say(cats:get("bar"))
        ';
    }
--- request
GET /test
--- response_body
true
false



=== TEST 4: number keys, string values
--- http_config
    lua_shared_dict cats 1m;
--- config
    location = /test {
        content_by_lua '
            local cats = ngx.shared.cats
            ngx.say(cats:set(1234, "cat"))
            ngx.say(cats:set("1234", "dog"))
            ngx.say(cats:set(256, "bird"))
            ngx.say(cats:get(1234))
            ngx.say(cats:get("1234"))
            ngx.say(cats:get("256"))
        ';
    }
--- request
GET /test
--- response_body
false
false
false
dog
dog
bird



=== TEST 5: different-size values set to the same key
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "hello")
            ngx.say(dogs:get("foo"))
            dogs:set("foo", "hello, world")
            ngx.say(dogs:get("foo"))
            dogs:set("foo", "hello")
            ngx.say(dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
hello
hello, world
hello



=== TEST 6: expired entries
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0.01)
            ngx.location.capture("/sleep/0.01")
            ngx.say(dogs:get("foo"))
        ';
    }
    location ~ '^/sleep/(.+)' {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
nil



=== TEST 7: not yet expired entries
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0.5)
            ngx.location.capture("/sleep/0.01")
            ngx.say(dogs:get("foo"))
        ';
    }
    location ~ '^/sleep/(.+)' {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
32



=== TEST 8: forcibly override other valid entries
--- http_config
    lua_shared_dict dogs 100k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local i = 0
            while i < 1000 do
                i = i + 1
                local val = string.rep(" hello " .. i, 10)
                local override = dogs:set("key_" .. i, val)
                if override then
                    break
                end
            end
            ngx.say("abort at ", i)
            ngx.say("value: ", dogs:get("key_" .. i))
        ';
    }
--- pipelined_requests eval
["GET /test", "GET /test"]
--- response_body eval
["abort at 353\nvalue: " . (" hello 353" x 10) . "\n",
"abort at 1\nvalue: " . (" hello 1" x 10) . "\n"
]



=== TEST 9: dogs and cats dicts
--- http_config
    lua_shared_dict dogs 1m;
    lua_shared_dict cats 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local cats = ngx.shared.cats
            dogs:set("foo", 32)
            cats:set("foo", "hello, world")
            ngx.say(dogs:get("foo"))
            ngx.say(cats:get("foo"))
            dogs:set("foo", 56)
            ngx.say(dogs:get("foo"))
            ngx.say(cats:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
32
hello, world
56
hello, world



=== TEST 10: get non-existent keys
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            ngx.say(dogs:get("foo"))
            ngx.say(dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
nil
nil

