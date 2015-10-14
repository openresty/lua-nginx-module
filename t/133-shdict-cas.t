# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
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

=== TEST 1: old value without flags
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "old-value")
            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)

            local success, err, forcible, current_value, current_flags = dogs:cas("foo", "new-value", 0, 0, value, flags)
            ngx.say(success, " ", err, " ", forcible, " ", current_value, " ", current_flags)

            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)
        ';
    }
--- request
GET /test
--- response_body
old-value nil
true nil false nil nil
new-value nil
--- no_error_log
[error]



=== TEST 2: old-value with flags
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "old-value", 0, 1)
            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)

            local success, err, forcible, current_value, current_flags = dogs:cas("foo", "new-value", 0, 2, value, flags)
            ngx.say(success, " ", err, " ", forcible, " ", current_value, " ", current_flags)

            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)
        ';
    }
--- request
GET /test
--- response_body
old-value 1
true nil false nil nil
new-value 2
--- no_error_log
[error]



=== TEST 3: only check value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "old-value", 0, 1)
            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)

            local success, err, forcible, current_value, current_flags = dogs:cas("foo", "new-value", 0, 2, value)
            ngx.say(success, " ", err, " ", forcible, " ", current_value, " ", current_flags)

            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)
        ';
    }
--- request
GET /test
--- response_body
old-value 1
true nil false nil nil
new-value 2
--- no_error_log
[error]



=== TEST 4: only check flags
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "old-value", 0, 1)
            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)

            local success, err, forcible, current_value, current_flags = dogs:cas("foo", "new-value", 0, 2, nil, flags)
            ngx.say(success, " ", err, " ", forcible, " ", current_value, " ", current_flags)

            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)
        ';
    }
--- request
GET /test
--- response_body
old-value 1
true nil false nil nil
new-value 2
--- no_error_log
[error]



=== TEST 5: only check flags(flags is nil)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "old-value", 0, 0)
            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)

            local success, err, forcible, current_value, current_flags = dogs:cas("foo", "new-value", 0, 2, nil, flags)
            ngx.say(success, " ", err, " ", forcible, " ", current_value, " ", current_flags)

            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)
        ';
    }
--- request
GET /test
--- response_body
old-value nil
true nil false nil nil
new-value 2
--- no_error_log
[error]



=== TEST 6: check failed (value)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "old-value", 0, 1)
            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)

            local success, err, forcible, current_value, current_flags = dogs:cas("foo", "new-value", 0, 2, "oldvalue", flags)
            ngx.say(success, " ", err, " ", forcible, " ", current_value, " ", current_flags)

            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)
        ';
    }
--- request
GET /test
--- response_body
old-value 1
false not matched false old-value 1
old-value 1
--- no_error_log
[error]



=== TEST 7: check failed (flags)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "old-value", 0, 1)
            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)

            local success, err, forcible, current_value, current_flags = dogs:cas("foo", "new-value", 0, 2, value, nil)
            ngx.say(success, " ", err, " ", forcible, " ", current_value, " ", current_flags)

            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)
        ';
    }
--- request
GET /test
--- response_body
old-value 1
false not matched false old-value 1
old-value 1
--- no_error_log
[error]



=== TEST 8: sometimes check failed
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 0)
            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)

            local i = 1

            while i <= 6 do
                if i % 2 == 1 then
                    dogs:incr("foo", 1)
                end

                local success, err, forcible, current_value, current_flags = dogs:cas("foo", value + 1, 0, 0, value, flags)
                if success then
                    ngx.say("success at time: ", i)
                else
                    value = current_value
                    flags = current_flags
                    ngx.say(success, " ", err, " ", forcible, " ", value, " ", flags)
                end

                i = i + 1
            end

            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)
        ';
    }
--- request
GET /test
--- response_body
0 nil
false not matched false 1 nil
success at time: 2
false not matched false 3 nil
success at time: 4
false not matched false 5 nil
success at time: 6
6 nil
--- no_error_log
[error]



=== TEST 9: sometimes check failed(set nil: delete)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 0)
            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)

            local i = 1

            while i <= 6 do
                local success, err, forcible, current_value, current_flags = dogs:cas("foo", nil, 0, 0, value, flags)
                if success then
                    ngx.say("success at time: ", i)

                elseif err == "not found" then
                    dogs:add("foo", 0)
                    ngx.say(success, " ", err, " ", forcible, " ", current_value, " ", current_flags)

                else
                    value = current_value
                    flags = current_flags
                    ngx.say(success, " ", err, " ", forcible, " ", value, " ", flags)
                end

                i = i + 1
            end

            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)
        ';
    }
--- request
GET /test
--- response_body
0 nil
success at time: 1
false not found false nil nil
success at time: 3
false not found false nil nil
success at time: 5
false not found false nil nil
0 nil
--- no_error_log
[error]



=== TEST 10: check failed (value type)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", string.char(0))
            local value, flags = dogs:get("foo")

            local success, err, forcible, current_value, current_flags = dogs:cas("foo", "new-value", 0, 2, false, flags)
            ngx.say(success, " ", err, " ", forcible)

            local value, flags = dogs:get("foo")
            ngx.say("value == char(0): ", value == string.char(0))
        ';
    }
--- request
GET /test
--- response_body
false not matched false
value == char(0): true
--- no_error_log
[error]



=== TEST 11: value is boolean
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", true, 0, 1)
            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)

            local success, err, forcible, current_value, current_flags = dogs:cas("foo", false, 0, 2, value, flags)
            ngx.say(success, " ", err, " ", forcible, " ", current_value, " ", current_flags)

            local value, flags = dogs:get("foo")
            ngx.say(value, " ", flags)
        ';
    }
--- request
GET /test
--- response_body
true 1
true nil false nil nil
false 2
--- no_error_log
[error]

