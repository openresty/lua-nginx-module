# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#master_on();
workers(1);
#worker_connections(1014);
#log_level('warn');
#master_process_enabled(1);

repeat_each(1);
plan tests => repeat_each() * (blocks() * 2 + 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: set new http header for sub-request
--- config
    location /sub {
        content_by_lua '
            local headers = ngx.req.get_headers()
            ngx.say(headers["X-Sub-Request-Header"])
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub",
              { method = ngx.HTTP_GET,
                extra_headers = { ["X-Sub-Request-Header"] = "foo" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /main
--- response_body
foo



=== TEST 2: inherit http header of the parent request
--- config
    location /sub {
        content_by_lua '
            local headers = ngx.req.get_headers()
            ngx.say(headers["X-Parent-Request-Header"])
            ngx.say(headers["X-Sub-Request-Header"])
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub",
              { method = ngx.HTTP_GET,
                extra_headers = { ["X-Sub-Request-Header"] = "bar" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /main
--- more_headers
X-Parent-Request-Header: foo
--- response_body
foo
bar



=== TEST 3: overwrite custom http header of the parent request
--- config
    location /sub {
        content_by_lua '
            local headers = ngx.req.get_headers()
            ngx.say(headers["X-Parent-Request-Header"])
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub",
              { method = ngx.HTTP_GET,
                extra_headers = { ["X-Parent-Request-Header"] = "bar" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /main
--- more_headers
X-Parent-Request-Header: foo
--- response_body
bar



=== TEST 4: Content-Length of the GET sub-request issued from POST request
--- config
    location /sub {
        content_by_lua '
            local headers = ngx.req.get_headers()
            ngx.say("Content-Length: ", headers["Content-Length"])
            ngx.req.read_body()
            ngx.say("Message-Body: ", ngx.req.get_body_data() or "nil")
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub",
              { method = ngx.HTTP_GET })
            ngx.print(res.body)
        ';
    }
--- request
POST /main
hello, world
--- response_body
Content-Length: nil
Message-Body: nil



=== TEST 5: inherit message-body and Content-Length from the parent request
--- config
    location /sub {
        content_by_lua '
            local headers = ngx.req.get_headers()
            ngx.say("Content-Length: ", headers["Content-Length"])
            ngx.req.read_body()
            ngx.say("Message-Body: ", ngx.req.get_body_data() or "nil")
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub",
              { method = ngx.HTTP_POST })
            ngx.print(res.body)
        ';
    }
--- request
POST /main
hello, world
--- response_body
Content-Length: 12
Message-Body: hello, world



=== TEST 6: overwrite message body and Content-Length of the parent request
--- config
    location /sub {
        content_by_lua '
            local headers = ngx.req.get_headers()
            ngx.say("Content-Length: ", headers["Content-Length"])
            ngx.req.read_body()
            ngx.say("Message-Body: ", ngx.req.get_body_data() or "nil")
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub",
              { method = ngx.HTTP_POST, body="foobar" })
            ngx.print(res.body)
        ';
    }
--- request
POST /main
hello, world
--- response_body
Content-Length: 6
Message-Body: foobar



=== TEST 7: incorrect type of the extra_headers option
--- config
    location /sub {
        content_by_lua '
            ngx.say("Sub page should not be accessed in this test.")
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub",
              { method = ngx.HTTP_GET,
                extra_headers = "string" })
            ngx.print(res.body)
        ';
    }
--- request
GET /main
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log chop
Bad extra_headers option value type



=== TEST 8: incorrect key type for the extra_headers option
--- config
    location /sub {
        content_by_lua '
            ngx.say("Sub page should not be accessed in this test.")
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub",
              { method = ngx.HTTP_GET,
                extra_headers = { [1]="key is not string" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /main
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log chop
attempt to use a non-string key in the "extra_headers" option table



=== TEST 9: incorrect value type for the extra_headers option
--- config
    location /sub {
        content_by_lua '
            ngx.say("Sub page should not be accessed in this test.")
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub",
              { method = ngx.HTTP_GET,
                extra_headers = { ["non_string_value"]=true } })
            ngx.print(res.body)
        ';
    }
--- request
GET /main
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log chop
attempt to use a non-string variable value in the "extra_headers" option table



