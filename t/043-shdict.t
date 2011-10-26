# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 4);

#no_diff();
no_long_string();
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
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
            val = dogs:get("bah")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
32 number
10502 number



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
            local val = cats:get("foo")
            ngx.say(val, " ", type(val))
            val = cats:get("baz")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
3.14159 number
3.96 number



=== TEST 3: string key, boolean value
--- http_config
    lua_shared_dict cats 1m;
--- config
    location = /test {
        content_by_lua '
            local cats = ngx.shared.cats
            cats:set("foo", true)
            cats:set("bar", false)
            local val = cats:get("foo")
            ngx.say(val, " ", type(val))
            val = cats:get("bar")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
true boolean
false boolean



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
            local val = cats:get("256")
            ngx.say(val, " ", type(val))
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
bird string



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
            ngx.say("cur value: ", dogs:get("key_" .. i))
            if i > 1 then
                ngx.say("1st value: ", dogs:get("key_1"))
            end
            if i > 2 then
                ngx.say("2nd value: ", dogs:get("key_2"))
            end
        ';
    }
--- pipelined_requests eval
["GET /test", "GET /test"]
--- response_body eval
["abort at 353\ncur value: " . (" hello 353" x 10) . "\n1st value: nil\n2nd value: " . (" hello 2" x 10) . "\n",
"abort at 1\ncur value: " . (" hello 1" x 10) . "\n"
]



=== TEST 9: forcibly override other valid entries and test LRU
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
                if i == 10 then
                    dogs:get("key_1")
                end
                local override = dogs:set("key_" .. i, val)
                if override then
                    break
                end
            end
            ngx.say("abort at ", i)
            ngx.say("cur value: ", dogs:get("key_" .. i))
            if i > 1 then
                ngx.say("1st value: ", dogs:get("key_1"))
            end
            if i > 2 then
                ngx.say("2nd value: ", dogs:get("key_2"))
            end
        ';
    }
--- pipelined_requests eval
["GET /test", "GET /test"]
--- response_body eval
["abort at 353\ncur value: " . (" hello 353" x 10) . "\n1st value: " . (" hello 1" x 10) . "\n2nd value: nil\n",
"abort at 2\ncur value: " . (" hello 2" x 10) . "\n1st value: " . (" hello 1" x 10) . "\n"
]



=== TEST 10: dogs and cats dicts
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



=== TEST 11: get non-existent keys
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



=== TEST 12: not feed the object into the call
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local rc, err = pcall(dogs.set, "foo", 3, 0.01)
            ngx.say(rc, " ", err)
            rc, err = pcall(dogs.set, "foo", 3)
            ngx.say(rc, " ", err)
            rc, err = pcall(dogs.get, "foo")
            ngx.say(rc, " ", err)
        ';
    }
--- request
GET /test
--- response_body
false bad argument #1 to '?' (userdata expected, got string)
false expecting 3 or 4 arguments, but only seen 2
false expecting exactly two arguments, but only seen 1



=== TEST 13: too big value
--- http_config
    lua_shared_dict dogs 50k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local rc, err = pcall(dogs.set, dogs, "foo", string.rep("helloworld", 10000))
            ngx.say(rc, " ", err)
        ';
    }
--- request
GET /test
--- response_body
false failed to allocate memory for shared_dict dogs (maybe the total capacity is too small?)



=== TEST 14: too big key
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local key = string.rep("a", 65535)
            local rc, err = pcall(dogs.set, dogs, key, "hello")
            ngx.say(rc, " ", err)
            ngx.say(dogs:get(key))

            key = string.rep("a", 65536)
            rc, err = pcall(dogs.set, dogs, key, "world")
            ngx.say(rc, " ", err)

        ';
    }
--- request
GET /test
--- response_body
true false
hello
false the key argument is more than 65535 bytes: 65536



=== TEST 15: bad value type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local rc, err = pcall(dogs.set, dogs, "foo", dogs)
            ngx.say(rc, " ", err)
        ';
    }
--- request
GET /test
--- response_body
false unsupported value type for key "foo" in shared_dict "dogs": userdata



=== TEST 16: set nil after setting values
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            ngx.say(dogs:get("foo"))
            dogs:set("foo", nil)
            ngx.say(dogs:get("foo"))
            dogs:set("foo", "hello, world")
            ngx.say(dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
32
nil
hello, world



=== TEST 17: set nil at first
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", nil)
            ngx.say(dogs:get("foo"))
            dogs:set("foo", "hello, world")
            ngx.say(dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
nil
hello, world


=== TEST 17: set nil at first
--- http_config
    lua_shared_dict dogs 100k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local i = 0
            while i < 1000 do
                i = i + 1
                local val = string.rep("hello", i )
                local override = dogs:set("key_" .. i, val)
                if override then
                    break
                end
            end
            ngx.say("abort at ", i)
        ';
    }
--- request
GET /test
--- response_body
abort at 139

