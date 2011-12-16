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

=== TEST 1: flush wait - content
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- response_body
hello, world
hiya



=== TEST 2: flush no wait - content
--- config
    send_timeout 500ms;
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(false)
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- response_body
hello, world
hiya



=== TEST 3: flush wait - rewrite
--- config
    location /test {
        rewrite_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
        ';
        content_by_lua return;
    }
--- request
GET /test
--- response_body
hello, world
hiya



=== TEST 4: flush no wait - rewrite
--- config
    location /test {
        rewrite_by_lua '
            ngx.say("hello, world")
            ngx.flush(false)
            ngx.say("hiya")
        ';
        content_by_lua return;
    }
--- request
GET /test
--- response_body
hello, world
hiya



=== TEST 5: http 1.0
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya



=== TEST 6: flush wait - big data
--- config
    location /test {
        content_by_lua '
            ngx.say(string.rep("a", 1024 * 64))
            ngx.flush(true)
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- response_body
hello, world
hiya
--- SKIP



=== TEST 7: flush wait - content
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
            ngx.flush(true)
        ';
    }
    location /sub {
        echo sub;
    }
--- request
GET /test
--- response_body
hello, world
sub

