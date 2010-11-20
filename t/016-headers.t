# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => blocks() * repeat_each() * 3;

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header.content_type = "text/my-plain";
            ngx.say("Hi");
        ';
    }
--- request
GET /read
--- response_headers
Content-Type: text/my-plain
--- response_body
Hi



=== TEST 2: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header.content_length = "text/my-plain";
            ngx.say("Hi");
        ';
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- response_headers
Content-Type: text/html
--- error_code: 500



=== TEST 3: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header.content_length = 3
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- response_headers
Content-Length: 3
--- response_body
Hello



=== TEST 4: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.status = 302;
            ngx.header["Location"] = "http://www.taobao.com/foo";
        ';
    }
--- request
GET /read
--- response_headers
Location: http://www.taobao.com/foo
--- response_body
--- error_code: 302



=== TEST 5: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header.content_length = 3
            ngx.header.content_length = nil
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- response_headers
!Content-Length
--- response_body
Hello



=== TEST 6: set multi response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header["X-Foo"] = {"a", "bc"}
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- raw_response_headers_like chomp
X-Foo: a\r\n.*?X-Foo: bc$
--- response_body
Hello



=== TEST 7: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header.content_type = {"a", "bc"}
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- response_headers
Content-Type: bc
--- response_body
Hello



=== TEST 8: set multi response content-type header and clears it
--- config
    location /read {
        content_by_lua '
            ngx.header["X-Foo"] = {"a", "bc"}
            ngx.header["X-Foo"] = {}
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- response_headers
!X-Foo
--- response_body
Hello



=== TEST 9: set multi response content-type header and clears it
--- config
    location /read {
        content_by_lua '
            ngx.header["X-Foo"] = {"a", "bc"}
            ngx.header["X-Foo"] = nil
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- response_headers
!X-Foo
--- response_body
Hello



=== TEST 10: set multi response content-type header (multiple times)
--- config
    location /read {
        content_by_lua '
            ngx.header["X-Foo"] = {"a", "bc"}
            ngx.header["X-Foo"] = {"a", "abc"}
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- raw_response_headers_like chomp
X-Foo: a\r\n.*?X-Foo: abc$
--- response_body
Hello

