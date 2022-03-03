# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 - 4);

#log_level("info");
#no_long_string();

run_tests();

__DATA__

=== TEST 1: server_rewrite_by_lua_block in http
--- http_config
    server_rewrite_by_lua_block {
        ngx.ctx.a = "server_rewrite_by_lua_block in http"
    }
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(ngx.ctx.a)
            ngx.log(ngx.INFO, ngx.ctx.a)
        }
    }
--- request
GET /lua
--- response_body
server_rewrite_by_lua_block in http
--- error_log
server_rewrite_by_lua_block in http
--- no_error_log
[error]



=== TEST 2: server_rewrite_by_lua_block in server
--- config
    server_rewrite_by_lua_block {
        ngx.log(ngx.INFO, "server_rewrite_by_lua_block in server")
    }
    location /lua {
        content_by_lua_block {
            ngx.say("OK")
        }
    }
--- request
GET /lua
--- response_body
OK
--- error_log
server_rewrite_by_lua_block in server
--- no_error_log
[error]



=== TEST 3: server_rewrite_by_lua_block overwrite by server
--- http_config
    server_rewrite_by_lua_block {
        ngx.log(ngx.INFO, "server_rewrite_by_lua_block in http")
    }
--- config
    server_rewrite_by_lua_block {
        ngx.log(ngx.INFO, "server_rewrite_by_lua_block in server")
    }
    location /lua {
        content_by_lua_block {
            ngx.say("OK")
        }
    }
--- request
GET /lua
--- response_body
OK
--- error_log
server_rewrite_by_lua_block in server
--- no_error_log
[error]



=== TEST 4: sleep
--- config
    server_rewrite_by_lua_block {
        ngx.sleep(0.001)
        ngx.log(ngx.INFO, "server_rewrite_by_lua_block in server")
    }
    location /lua {
        content_by_lua_block {
            ngx.say("OK")
        }
    }
--- request
GET /lua
--- response_body
OK
--- error_log
server_rewrite_by_lua_block in server
--- no_error_log
[error]



=== TEST 5: ngx.exit(ngx.OK)
--- config
    server_rewrite_by_lua_block {
        ngx.log(ngx.INFO, "ngx.exit")
        ngx.exit(ngx.OK)
    }
    location /lua {
        content_by_lua_block {
        ngx.say("OK")
        }
    }
--- request
GET /lua
--- response_body
OK
--- error_log
ngx.exit
--- no_error_log
[error]



=== TEST 6: ngx.exit(503)
--- config
    server_rewrite_by_lua_block {
        ngx.exit(503)
    }
    location /lua {
        content_by_lua_block {
         ngx.log(ngx.ERR, "content_by_lua")
         ngx.say("OK")
        }
    }
--- request
GET /lua
--- error_code: 503
--- no_error_log
[error]



=== TEST 7: subrequests
--- config
    server_rewrite_by_lua_block {
        ngx.log(ngx.INFO, "is_subrequest:", ngx.is_subrequest)
    }

    location /lua {
        content_by_lua_block {
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
        }
    }

    location /sub {
        content_by_lua_block {
            ngx.say("OK")
        }
    }

--- request
GET /lua
--- response_body
OK
--- error_log
is_subrequest:false
is_subrequest:true
--- no_error_log
[error]



=== TEST 8: rewrite by ngx_http_rewrite_module
--- config
    server_rewrite_by_lua_block {
        ngx.log(ngx.INFO, "uri is ", ngx.var.uri)
    }

    rewrite ^ /re;

    location /re {
        content_by_lua_block {
            ngx.say("RE")
        }
    }

    location /ok {
        content_by_lua_block {
            ngx.say("OK")
        }
    }

--- request
GET /lua
--- response_body
RE
--- error_log
uri is /lua
--- no_error_log
[error]



=== TEST 9: exec
--- config
    server_rewrite_by_lua_block {
        if ngx.var.uri ~= "/ok" then
            ngx.exec("/ok")
        end
        ngx.log(ngx.INFO, "uri is ", ngx.var.uri)
    }

    location /ok {
        content_by_lua_block {
            ngx.say("OK")
        }
    }

--- request
GET /lua
--- response_body
OK
--- error_log
uri is /ok
--- no_error_log
[error]



=== TEST 10: server_rewrite_by_lua and rewrite_by_lua
--- http_config
    server_rewrite_by_lua_block {
        ngx.log(ngx.INFO, "server_rewrite_by_lua_block in http")
    }
--- config
    location /lua {
        rewrite_by_lua_block {
            ngx.log(ngx.INFO, "rewrite_by_lua_block in location")
        }
        content_by_lua_block {
            ngx.say("OK")
        }
    }
--- request
GET /lua
--- response_body
OK
--- error_log
server_rewrite_by_lua_block in http
rewrite_by_lua_block in location
--- no_error_log
[error]



=== TEST 11: server_rewrite_by_lua_file
--- http_config
    server_rewrite_by_lua_file 'html/foo.lua';
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("OK")
        }
    }
--- request
GET /lua
--- user_files
>>> foo.lua
ngx.log(ngx.INFO, "rewrite_by_lua_file in server")
--- response_body
OK
--- error_log
rewrite_by_lua_file in server
--- no_error_log
[error]



=== TEST 12: syntax error server_rewrite_by_lua_block in http
--- http_config
    server_rewrite_by_lua_block {
        'for end';
    }
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("OK")
        }
    }
--- request
GET /lua
--- ignore_response
--- error_log
failed to load inlined Lua code: server_rewrite_by_lua(nginx.conf:27):2: unexpected symbol near ''for end''
--- no_error_log
no_such_error



=== TEST 13: syntax error server_rewrite_by_lua_block in server
--- config
    server_rewrite_by_lua_block {
        'for end';
    }
    location /lua {
        content_by_lua_block {
            ngx.say("Hello world")
        }
    }
--- request
GET /lua
--- ignore_response
--- error_log
failed to load inlined Lua code: server_rewrite_by_lua(nginx.conf:41):2: unexpected symbol near ''for end''
--- no_error_log
no_such_error
