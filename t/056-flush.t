# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    $ENV{TEST_NGINX_POSTPONE_OUTPUT} = 1;
}

use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * 55;

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: flush wait - content
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            local ok, err = ngx.flush(true)
            if not ok then
                ngx.log(ngx.ERR, "flush failed: ", err)
                return
            end
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- response_body
hello, world
hiya
--- no_error_log
[error]
--- error_log
lua reuse free buf memory 13 >= 5



=== TEST 2: flush no wait - content
--- config
    send_timeout 500ms;
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            local ok, err = ngx.flush(false)
            if not ok then
                ngx.log(ngx.ERR, "flush failed: ", err)
                return
            end
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



=== TEST 5: http 1.0 (sync)
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
            ngx.flush(true)
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
Content-Length: 23
--- timeout: 5
--- error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op



=== TEST 6: http 1.0 (async)
--- config
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            local ok, err = ngx.flush(false)
            if not ok then
                ngx.log(ngx.WARN, "1: failed to flush: ", err)
            end
            ngx.say("hiya")
            local ok, err = ngx.flush(false)
            if not ok then
                ngx.log(ngx.WARN, "2: failed to flush: ", err)
            end
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
Content-Length: 23
--- error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op
1: failed to flush: buffering
2: failed to flush: buffering
--- timeout: 5



=== TEST 7: flush wait - big data
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



=== TEST 8: flush wait - content
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



=== TEST 9: http 1.0 (sync + buffering off)
--- config
    lua_http10_buffering off;
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
            ngx.flush(true)
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
!Content-Length
--- timeout: 5
--- no_error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op



=== TEST 10: http 1.0 (async)
--- config
    lua_http10_buffering on;
    location /test {
        lua_http10_buffering off;
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(false)
            ngx.say("hiya")
            ngx.flush(false)
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
!Content-Length
--- no_error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op
--- timeout: 5



=== TEST 11: http 1.0 (sync) - buffering explicitly off
--- config
    location /test {
        lua_http10_buffering on;
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
            ngx.flush(true)
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
Content-Length: 23
--- timeout: 5
--- error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op



=== TEST 12: http 1.0 (async) - buffering explicitly off
--- config
    location /test {
        lua_http10_buffering on;
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(false)
            ngx.say("hiya")
            ngx.flush(false)
            ngx.say("blah")
        ';
    }
--- request
GET /test HTTP/1.0
--- response_body
hello, world
hiya
blah
--- response_headers
Content-Length: 23
--- error_log
lua buffering output bufs for the HTTP 1.0 request
lua http 1.0 buffering makes ngx.flush() a no-op
--- timeout: 5



=== TEST 13: flush wait in a user coroutine
--- config
    location /test {
        content_by_lua '
            function f()
                ngx.say("hello, world")
                ngx.flush(true)
                coroutine.yield()
                ngx.say("hiya")
            end
            local c = coroutine.create(f)
            ngx.say(coroutine.resume(c))
            ngx.say(coroutine.resume(c))
        ';
    }
--- request
GET /test
--- stap2
F(ngx_http_lua_wev_handler) {
    printf("wev handler: wev:%d\n", $r->connection->write->ready)
}

global ids, cur

function gen_id(k) {
    if (ids[k]) return ids[k]
    ids[k] = ++cur
    return cur
}

F(ngx_http_handler) {
    delete ids
    cur = 0
}

/*
F(ngx_http_lua_run_thread) {
    id = gen_id($ctx->cur_co)
    printf("run thread %d\n", id)
}

probe process("/usr/local/openresty-debug/luajit/lib/libluajit-5.1.so.2").function("lua_resume") {
    id = gen_id($L)
    printf("lua resume %d\n", id)
}
*/

M(http-lua-user-coroutine-resume) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("resume %x in %x\n", c, p)
}

M(http-lua-entry-coroutine-yield) {
    println("entry coroutine yield")
}

/*
F(ngx_http_lua_coroutine_yield) {
    printf("yield %x\n", gen_id($L))
}
*/

M(http-lua-user-coroutine-yield) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("yield %x in %x\n", c, p)
}

F(ngx_http_lua_atpanic) {
    printf("lua atpanic(%d):", gen_id($L))
    print_ubacktrace();
}

M(http-lua-user-coroutine-create) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("create %x in %x\n", c, p)
}

F(ngx_http_lua_ngx_exec) { println("exec") }

F(ngx_http_lua_ngx_exit) { println("exit") }

F(ngx_http_writer) { println("http writer") }

--- response_body
hello, world
true
hiya
true
--- error_log
lua reuse free buf memory 13 >= 5



=== TEST 14: flush before sending out the header
--- config
    location /test {
        content_by_lua '
            ngx.flush()
            ngx.status = 404
            ngx.say("not found")
        ';
    }
--- request
GET /test
--- response_body
not found
--- error_code: 404
--- no_error_log
[error]



=== TEST 15: flush wait - gzip
--- config
    gzip             on;
    gzip_min_length  1;
    gzip_types       text/plain;

    location /test {
        content_by_lua '
            ngx.say("hello, world")
            local ok, err = ngx.flush(true)
            if not ok then
                ngx.log(ngx.ERR, "flush failed: ", err)
                return
            end
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- more_headers
Accept-Encoding: gzip
--- response_body_like: .{15}
--- response_headers
Content-Encoding: gzip
--- no_error_log
[error]



=== TEST 16: flush wait - gunzip
--- config
    location /test {
        gunzip on;
        content_by_lua '
            local f, err = io.open(ngx.var.document_root .. "/gzip.bin", "r")
            if not f then
                ngx.say("failed to open file: ", err)
                return
            end
            local data = f:read(100)
            ngx.header.content_encoding = "gzip"
            ngx.print(data)
            local ok, err = ngx.flush(true)
            if not ok then
                ngx.log(ngx.ERR, "flush failed: ", err)
                return
            end
        ';
    }
--- user_files eval
">>> gzip.bin
\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\x03\xb5\x19\xdb\x6e\x1b\xc7\xf5\x9d\x5f\x31\x5d\xa3\xa0\x84\x68\x2f\xbc\xc8\xb2\x28\x92\x85\x2d\x19\x8e\x01\x4b\x11\x6a\xa5\x69\x60\x18\xc2\x70\x77\xb8\x1c\x6b\xb9\xb3\x9e\x99\x25\xc5\x24\x06\x12\xe4\xa1\xcf\x45\x81\x16\x05\x8a\x3e\x14\x28\x5a\x04\x6d\x9f\xd3\xa2\x7d\xca\x0f\xd8\x4f\xfe\x81\xc0\xed\x67\xf4\x9c\xd9\x5d\x72\x79\x91\x25\x32\x91\x04\x51\x7b\xe6\x5c"
--- request
GET /test
--- ignore_response
--- no_error_log
[error]

