# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

#repeat_each(120);
repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 2);

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: no key found
--- config
    location /nil {
        content_by_lua '
            ngx.say(ngx.blah_blah == nil and "nil" or "not nil")
        ';
    }
--- request
GET /nil
--- response_body
nil
--- no_error_log
[error]



=== TEST 2: .status found
--- config
    location /nil {
        content_by_lua '
            ngx.say(ngx.status == nil and "nil" or "not nil")
        ';
    }
--- request
GET /nil
--- response_body
not nil
--- no_error_log
[error]



=== TEST 3: default to 0
--- config
    location /nil {
        content_by_lua '
            ngx.say(ngx.status);
        ';
    }
--- request
GET /nil
--- response_body
0
--- no_error_log
[error]



=== TEST 4: default to 0
--- config
    location /nil {
        content_by_lua '
            ngx.say("blah");
            ngx.say(ngx.status);
        ';
    }
--- request
GET /nil
--- response_body
blah
200
--- no_error_log
[error]



=== TEST 5: set 201
--- config
    location /201 {
        content_by_lua '
            ngx.status = 201;
            ngx.say("created");
        ';
    }
--- request
GET /201
--- response_body
created
--- error_code: 201
--- no_error_log
[error]



=== TEST 6: set "201"
--- config
    location /201 {
        content_by_lua '
            ngx.status = "201";
            ngx.say("created");
        ';
    }
--- request
GET /201
--- response_body
created
--- error_code: 201
--- no_error_log
[error]



=== TEST 7: set "201.7"
--- config
    location /201 {
        content_by_lua '
            ngx.status = "201.7";
            ngx.say("created");
        ';
    }
--- request
GET /201
--- response_body
created
--- error_code: 201
--- no_error_log
[error]



=== TEST 8: set "abc"
--- config
    location /201 {
        content_by_lua '
            ngx.status = "abc";
            ngx.say("created");
        ';
    }
--- request
GET /201
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- no_error_log
[crit]



=== TEST 9: set blah
--- config
    location /201 {
        content_by_lua '
            ngx.blah = 201;
            ngx.say("created");
        ';
    }
--- request
GET /201
--- response_body
created
--- no_error_log
[error]



=== TEST 10: set ngx.status before headers are sent
--- config
    location /t {
        content_by_lua '
            ngx.say("ok")
            ngx.status = 201
        ';
    }
--- request
    GET /t
--- response_body
ok
--- error_code: 200
--- error_log eval
qr/\[error\] .*? attempt to set ngx\.status after sending out response headers/



=== TEST 11: http 1.0 and ngx.status
--- config
    location /nil {
        content_by_lua '
            ngx.status = ngx.HTTP_UNAUTHORIZED
            ngx.say("invalid request")
            ngx.exit(ngx.HTTP_OK)
        ';
    }
--- request
GET /nil HTTP/1.0
--- response_body
invalid request
--- error_code: 401
--- no_error_log
[error]



=== TEST 12: github issue #221: cannot modify ngx.status for responses from ngx_proxy
--- config
    location = /t {
        proxy_pass http://127.0.0.1:$server_port/;
        header_filter_by_lua '
            if ngx.status == 206 then
                ngx.status = ngx.HTTP_OK
            end
        ';
    }

--- request
GET /t

--- more_headers
Range: bytes=0-4

--- response_body chop
<html

--- error_code: 200
--- no_error_log
[error]



=== TEST 13: 101 response has a complete status line
--- config
    location /t {
        content_by_lua '
            ngx.status = 101
            ngx.send_headers()
        ';
    }
--- request
GET /t
--- raw_response_headers_like: ^HTTP/1.1 101 Switching Protocols\r\n
--- error_code: 101
--- no_error_log
[error]
--- skip_eval: 3:$ENV{TEST_NGINX_USE_HTTP3}
--- no_http2



=== TEST 14: reading error status code
--- config
    location = /t {
        content_by_lua 'ngx.say("status = ", ngx.status)';
    }
--- raw_request eval
"GET /t\r\n"
--- http09
--- response_body
status = 9
--- no_error_log
[error]



=== TEST 15: err status
--- config
    location /nil {
        content_by_lua '
            ngx.exit(502)
        ';
        body_filter_by_lua '
            if ngx.arg[2] then
                ngx.log(ngx.WARN, "ngx.status = ", ngx.status)
            end
        ';
    }
--- request
GET /nil
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log
ngx.status = 502
--- no_error_log
[error]



=== TEST 16: ngx.status assignment should clear r->err_status
--- config
location = /t {
    return 502;
    header_filter_by_lua_block {
        if ngx.status == 502 then
            ngx.status = 654
            ngx.log(ngx.WARN, "ngx.status: ", ngx.status)
        end
    }
}
--- request
GET /t
--- response_body_like: Bad Gateway
--- error_log
ngx.status: 654
--- no_error_log
[error]
--- error_code: 654



=== TEST 17: set status and reason
--- config
location = /upstream {
    content_by_lua_block {
        local resp = require "ngx.resp"
        resp.set_status(500, "user defined reason")
        ngx.say("set_status_and_reason")
    }
}

location /t {
   content_by_lua_block {
       local sock = ngx.socket.tcp()
       local port = ngx.var.server_port
       local ok, err = sock:connect("127.0.0.1", port)
       if not ok then
           ngx.say("failed to connect: ", err)
           return
       end

       local req = "GET /upstream HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

       local bytes, err = sock:send(req)
       if not bytes then
           ngx.say("failed to send request: ", err)
           return
       end

       local found = false
       while true do
           local line, err, part = sock:receive()
           if line then
               if ngx.re.find(line, "HTTP/1.1 500 user defined reason") then
                   ngx.say("match")
               end
           else
               break
           end
       end

       sock:close()
   }
}
--- request
GET /t
--- response_body
match
--- no_error_log
[error]



=== TEST 18: set ngx.status in server_rewrite_by_lua_block
don't proxy_pass to upstream
--- config
    server_rewrite_by_lua_block {
        if ngx.var.uri == "/t" then
            ngx.status = 403
            ngx.say("Hello World")
        end
    }

    location /t {
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/u;
    }

    location /u {
        content_by_lua_block {
            ngx.say("From upstream")
        }
    }
--- request
GET /t HTTP/1.0
--- response_body
Hello World
--- error_code: 403
--- no_error_log
[error]



=== TEST 19: set ngx.status in rewrite_by_lua_block
don't proxy_pass to upstream
--- config
    location /t {
        rewrite_by_lua_block {
            ngx.status = 403
            ngx.say("Hello World")
        }
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/u;
    }

    location /u {
        content_by_lua_block {
            ngx.say("From upstream")
        }
    }
--- request
GET /t HTTP/1.0
--- response_body
Hello World
--- error_code: 403
--- no_error_log
[error]



=== TEST 20: set ngx.status in access_by_lua_block
don't proxy_pass to upstream
--- config
    location /t {
        access_by_lua_block {
            ngx.status = 403
            ngx.say("Hello World")
        }
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/u;
    }

    location /u {
        content_by_lua_block {
            ngx.say("From upstream")
        }
    }
--- request
GET /t HTTP/1.0
--- response_body
Hello World
--- error_code: 403
--- no_error_log
[error]



=== TEST 21: set ngx.status in server_rewrite_by_lua_block with sleep
don't proxy_pass to upstream
--- config
    server_rewrite_by_lua_block {
        if ngx.var.uri == "/t" then
            ngx.sleep(0.001)
            ngx.status = 403
            ngx.say("Hello World")
        end
    }

    location /t {
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/u;
    }

    location /u {
        content_by_lua_block {
            ngx.say("From upstream")
        }
    }
--- request
GET /t HTTP/1.0
--- response_body
Hello World
--- error_code: 403
--- no_error_log
[error]



=== TEST 22: set ngx.status in rewrite_by_lua_block with sleep
don't proxy_pass to upstream
--- config
    location /t {
        rewrite_by_lua_block {
            ngx.sleep(0.001)
            ngx.status = 403
            ngx.say("Hello World")
        }

        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/u;
    }

    location /u {
        content_by_lua_block {
            ngx.say("From upstream")
        }
    }
--- request
GET /t HTTP/1.0
--- response_body
Hello World
--- error_code: 403
--- no_error_log
[error]



=== TEST 23: set ngx.status in access_by_lua_block
don't proxy_pass to upstream
--- config
    location /t {
        access_by_lua_block {
            ngx.sleep(0.001)
            ngx.status = 403
            ngx.say("Hello World")
        }
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/u;
    }

    location /u {
        content_by_lua_block {
            ngx.say("From upstream")
        }
    }
--- request
GET /t HTTP/1.0
--- response_body
Hello World
--- error_code: 403
--- no_error_log
[error]
