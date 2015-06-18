# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    if (!defined $ENV{LD_PRELOAD}) {
        $ENV{LD_PRELOAD} = '';
    }

    if ($ENV{LD_PRELOAD} !~ /\bmockeagain\.so\b/) {
        $ENV{LD_PRELOAD} = "mockeagain.so $ENV{LD_PRELOAD}";
    }

    if ($ENV{MOCKEAGAIN} eq 'r') {
        $ENV{MOCKEAGAIN} = 'rw';

    } else {
        $ENV{MOCKEAGAIN} = 'w';
    }

    $ENV{TEST_NGINX_EVENT_TYPE} = 'poll';
    $ENV{MOCKEAGAIN_WRITE_TIMEOUT_PATTERN} = 'slow';
}

use lib 'lib';
use Test::Nginx::Socket::Lua;

log_level('debug');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

no_shuffle();
run_tests();

__DATA__

=== TEST 18: downstream cosocket used in two different threads. See issue #481
--- config
lua_socket_read_timeout 1ms;
lua_socket_send_timeout 1;
lua_socket_log_errors off;

        location /test {
            content_by_lua '

            function reader(req_socket)
               local data, err, partial
               -- First we receive in a blocking fashion so that ctx->downstream_co_ctx will be changed
               data, err, partial = req_socket:receive(1)
               if err ~= "timeout" then
                  ngx.log(ngx.ERR, "Did not get timeout in the receiving thread!")
                  return
               end
            
               -- Now, sleep so that coctx->data is changed to sleep handler
               ngx.sleep(3)
            end
            
            function writer(req_socket)
               local bytes, err
               -- send in a slow manner with a low timeout, so that the timeout handler will be
               bytes, err = req_socket:send("slow!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
               if err ~= "timeout" then
                  ngx.log(ngx.ERR, "Did not get timeout in the sending thread!")
                  return
               end
            end
            
            local req_socket, err = ngx.req.socket(true)
            if req_socket == nil then
               ngx.status = 500
               ngx.say("Unable to get request socket:", err)
               ngx.exit(500)
            end
            
            writer_thread = ngx.thread.spawn(writer, req_socket)
            reader_thread = ngx.thread.spawn(reader, req_socket)
            
            ngx.thread.wait(writer_thread)
            ngx.thread.wait(reader_thread)
            ngx.log(ngx.INFO, "The two threads finished")
';
        }
--- raw_request eval
["POST /test HTTP/1.1\r
Host: localhost\r
Connection: close\r
Content-Length: 1\r
\r
"
]
--- no_error_log
[error]
--- error_log: The two threads finished
--- ignore_response
