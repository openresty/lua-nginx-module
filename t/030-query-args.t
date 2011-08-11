# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

#repeat_each(2);
repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity

--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_query_args()
            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end
        ';
    }
--- request
GET /lua?a=3&b=4&c
--- response_body
a = 3
b = 4
c = true



=== TEST 2: args take no value
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_query_args()
            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end
        ';
    }
--- request
GET /lua?foo&bar=42
--- response_body
bar = 42
foo = true



=== TEST 3: arg key and value escaped
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_query_args()
            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end
        ';
    }
--- request
GET /lua?%3d&b%20r=4%61+2
--- response_body
= = true
b r = 4a 2



=== TEST 4: empty
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_query_args()
            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end

            ngx.say("done")
        ';
    }
--- request
GET /lua
--- response_body
done



=== TEST 5: empty arg, but with = and &
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_query_args()
            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end

            ngx.say("done")
        ';
    }
--- request
GET /lua?=&&
--- response_body
done

