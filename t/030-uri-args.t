# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

no_root_location();

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_uri_args()
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
            local args = ngx.req.get_uri_args()
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
GET /lua?foo&baz=&bar=42
--- response_body
bar = 42
baz = 
foo = true



=== TEST 3: arg key and value escaped
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_uri_args()
            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end

            ngx.say("again...")

            args = ngx.req.get_uri_args()
            keys = {}
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
again...
= = true
b r = 4a 2



=== TEST 4: empty
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_uri_args()
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
            local args = ngx.req.get_uri_args()
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



=== TEST 6: multi-value keys
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_uri_args()
            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                local val = args[key]
                if type(val) == "table" then
                    ngx.say(key, " = [", table.concat(val, ", "), "]")
                else
                    ngx.say(key, " = ", val)
                end
            end

            ngx.say("done")
        ';
    }
--- request
GET /lua?foo=32&foo==&foo=baz
--- response_body
foo = [32, =, baz]
done



=== TEST 7: multi-value keys
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_uri_args()
            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                local val = args[key]
                if type(val) == "table" then
                    ngx.say(key, " = [", table.concat(val, ", "), "]")
                else
                    ngx.say(key, " = ", val)
                end
            end

            ngx.say("done")
        ';
    }
--- request
GET /lua?foo=32&foo==&bar=baz
--- response_body
bar = baz
foo = [32, =]
done



=== TEST 8: empty arg
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_uri_args()
            local keys = {}
            -- ngx.say(args)
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
GET /lua?&=
--- response_body
done



=== TEST 9: = in value
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_uri_args()
            local keys = {}
            -- ngx.say(args)
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
GET /lua?foo===
--- response_body
foo = ==
done



=== TEST 10: empty key, but non-emtpy values
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_uri_args()
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
GET /lua?=hello&=world
--- response_body
done



=== TEST 11: updating args with $args
--- config
    location /lua {
        content_by_lua '
            local args = ngx.req.get_uri_args()
            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end

            ngx.say("updating args...")

            ngx.var.args = "a=3&b=4"

            local args = ngx.req.get_uri_args()
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
GET /lua?foo=bar
--- response_body
foo = bar
updating args...
a = 3
b = 4
done



=== TEST 12: rewrite args
--- config
    location /bar {
        echo $query_string;
    }
    location /foo {
        #set $args 'hello';
        rewrite_by_lua '
            ngx.req.set_uri("/bar");
            ngx.req.set_uri_args("hello")
        ';
        proxy_pass http://127.0.0.1:$server_port;
    }
--- request
    GET /foo?world
--- response_body
hello



=== TEST 13: rewrite args (not break cycle by default)
--- config
    location /bar {
        echo "bar: $uri?$args";
    }
    location /foo {
        #set $args 'hello';
        rewrite_by_lua '
            ngx.req.set_uri("/bar")
            ngx.req.set_uri_args("hello")
        ';
        echo "foo: $uri?$args";
    }
--- request
    GET /foo?world
--- response_body
bar: /bar?hello



=== TEST 14: rewrite (not break cycle explicitly)
--- config
    location /bar {
        echo "bar: $uri?$args";
    }
    location /foo {
        #set $args 'hello';
        rewrite_by_lua '
            ngx.req.set_uri("/bar", false)
            ngx.req.set_uri_args("hello")
        ';
        echo "foo: $uri?$args";
    }
--- request
    GET /foo?world
--- response_body
bar: /bar?hello



=== TEST 15: rewrite (break cycle explicitly)
--- config
    location /bar {
        echo "bar: $uri?$args";
    }
    location /foo {
        #set $args 'hello';
        rewrite_by_lua '
            ngx.req.set_uri("/bar", true)
            ngx.req.set_uri_args("hello")
        ';
        echo "foo: $uri?$args";
    }
--- request
    GET /foo?world
--- response_body
foo: /bar?hello



=== TEST 16: rewrite uri (zero-length)
--- config
    location /foo {
        #set $args 'hello';
        rewrite_by_lua '
            local res, err = pcall(ngx.req.set_uri, "")
            ngx.say("err: ", err)
        ';
        echo "foo: $uri?$args";
    }
--- request
    GET /foo?world
--- response_body
err: attempt to use zero-length uri
foo: /foo?world

