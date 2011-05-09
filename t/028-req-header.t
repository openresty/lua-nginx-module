# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: random access req headers
--- config
    location /req-header {
        content_by_lua '
            ngx.say("Foo: ", ngx.req.header["Foo"] or "nil")
            ngx.say("Bar: ", ngx.req.header["Bar"] or "nil")
        ';
    }
--- request
GET /req-header
--- more_headers
Foo: bar
Bar: baz
--- response_body
Foo: bar
Bar: baz



=== TEST 2: iterating through headers
--- config
    location /req-header {
        content_by_lua '
            local h = {}
            for k, v in pairs(ngx.req.header) do
                h[k] = v
            end
            ngx.say("Foo: ", h["Foo"] or "nil")
            ngx.say("Bar: ", h["Bar"] or "nil")
        ';
    }
--- request
GET /req-header
--- more_headers
Foo: bar
Bar: baz
--- response_body
Foo: bar
Bar: baz



=== TEST 3: setting req header table
--- config
    location /req-header {
        content_by_lua '
            ngx.req.header.foo = 3;
            ngx.say(ngx.req.header.foo)
        ';
    }
--- request
GET /req-header
--- more_headers
Foo: bar
Bar: baz
--- response_body
3

