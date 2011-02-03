# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

#$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;

no_long_string();

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)
        ';
    }
    location /a {
        echo -n a;
    }
    location /b {
        echo -n b;
    }
--- request
    GET /foo
--- response_body
res1.status = 200
res1.body = a
res2.status = 200
res2.body = b



=== TEST 2: capture multi in series
--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)

            res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            ngx.say("2 res1.status = " .. res1.status)
            ngx.say("2 res1.body = " .. res1.body)
            ngx.say("2 res2.status = " .. res2.status)
            ngx.say("2 res2.body = " .. res2.body)

        ';
    }
    location /a {
        echo -n a;
    }
    location /b {
        echo -n b;
    }
--- request
    GET /foo
--- response_body
res1.status = 200
res1.body = a
res2.status = 200
res2.body = b
2 res1.status = 200
2 res1.body = a
2 res2.status = 200
2 res2.body = b



=== TEST 3: capture multi in subrequest
--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }

            local n = ngx.var.arg_n

            ngx.say(n .. " res1.status = " .. res1.status)
            ngx.say(n .. " res1.body = " .. res1.body)
            ngx.say(n .. " res2.status = " .. res2.status)
            ngx.say(n .. " res2.body = " .. res2.body)
        ';
    }

    location /main {
        content_by_lua '
            res = ngx.location.capture("/foo?n=1")
            ngx.say("top res.status = " .. res.status)
            ngx.say("top res.body = [" .. res.body .. "]")
        ';
    }

    location /a {
        echo -n a;
    }

    location /b {
        echo -n b;
    }
--- request
    GET /main
--- response_body
top res.status = 200
top res.body = [1 res1.status = 200
1 res1.body = a
1 res2.status = 200
1 res2.body = b
]



=== TEST 4: capture multi in parallel
--- config
    location ~ '^/(foo|bar)$' {
        set $tag $1;
        content_by_lua '
            local res1, res2
            if ngx.var.tag == "foo" then
                res1, res2 = ngx.location.capture_multi{
                    { "/a" },
                    { "/b" },
                }
            else
                res1, res2 = ngx.location.capture_multi{
                    { "/c" },
                    { "/d" },
                }
            end

            local n = ngx.var.arg_n

            ngx.say(n .. " res1.status = " .. res1.status)
            ngx.say(n .. " res1.body = " .. res1.body)
            ngx.say(n .. " res2.status = " .. res2.status)
            ngx.say(n .. " res2.body = " .. res2.body)
        ';
    }

    location /main {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/foo?n=1" },
                { "/bar?n=2" },
            }

            ngx.say("top res1.status = " .. res1.status)
            ngx.say("top res1.body = [" .. res1.body .. "]")
            ngx.say("top res2.status = " .. res2.status)
            ngx.say("top res2.body = [" .. res2.body .. "]")
        ';
    }

    location ~ '^/([abcd])$' {
        echo -n $1;
    }
--- request
    GET /main
--- response_body
top res1.status = 200
top res1.body = [1 res1.status = 200
1 res1.body = a
1 res2.status = 200
1 res2.body = b
]
top res2.status = 200
top res2.body = [2 res1.status = 200
2 res1.body = c
2 res2.status = 200
2 res2.body = d
]



=== TEST 5: memc sanity
--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)
        ';
    }
    location ~ '^/[ab]$' {
        set $memc_key $uri;
        set $memc_value hello;
        set $memc_cmd set;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /foo
--- response_body eval
"res1.status = 200
res1.body = STORED\r

res2.status = 200
res2.body = STORED\r

"
--- SKIP


=== TEST 5: memc muti + multi
--- config
    location /main {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/foo?n=1" },
                { "/bar?n=2" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)
        ';
    }
    location ~ '^/(?:foo|bar)$' {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            local n = ngx.var.arg_n
            ngx.say(n .. " res1.status = " .. res1.status)
            ngx.say(n .. " res1.body = " .. res1.body)
            ngx.say(n .. " res2.status = " .. res2.status)
            ngx.say(n .. " res2.body = " .. res2.body)
        ';
    }
    location ~ '^/[ab]$' {
        set $memc_key $uri;
        set $memc_value hello;
        set $memc_cmd set;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /foo
--- response_body eval
"res1.status = 200
res1.body = STORED\r

res2.status = 200
res2.body = STORED\r

"
--- SKIP

