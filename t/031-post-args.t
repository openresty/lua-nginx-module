# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /lua {
        lua_need_request_body on;
        content_by_lua '
            local args = ngx.req.get_post_args()
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
POST /lua
a=3&b=4&c
--- response_body
a = 3
b = 4
c = true



=== TEST 2: lua_need_request_body off
--- config
    location /lua {
        lua_need_request_body off;
        content_by_lua '
            local args = ngx.req.get_post_args()
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
POST /lua
a=3&b=4&c
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 3: empty request body
--- config
    location /lua {
        lua_need_request_body on;
        content_by_lua '
            local args = ngx.req.get_post_args()
            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                local val = args[key]
                if type(val) == "table" then
                    ngx.say(key, ": ", table.concat(val, ", "))
                else
                    ngx.say(key, ": ", val)
                end
            end
        ';
    }
--- request
POST /lua
--- response_body

