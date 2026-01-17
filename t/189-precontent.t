# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = <<_EOC_;
$t::StapThread::GCScript

F(ngx_http_lua_check_broken_connection) {
    println("lua check broken conn")
}

F(ngx_http_lua_request_cleanup) {
    println("lua req cleanup")
}
_EOC_

our $StapScript = $t::StapThread::StapScript;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 6);

#log_level("info");
#no_long_string();

run_tests();

__DATA__

=== TEST 1: precontent_by_lua_block basic test
--- config
    location /lua {
        precontent_by_lua_block {
            ngx.log(ngx.INFO, "precontent_by_lua_block executed")
        }
        content_by_lua_block {
            ngx.say("content phase executed")
        }
    }
--- request
GET /lua
--- response_body
content phase executed
--- error_log
precontent_by_lua_block executed
--- no_error_log
[error]



=== TEST 2: precontent_by_lua_block with ngx.exit(ngx.OK)
--- config
    location /lua {
        precontent_by_lua_block {
            ngx.log(ngx.INFO, "precontent phase executed")
            ngx.exit(ngx.OK)
        }
        content_by_lua_block {
            ngx.say("content phase executed")
        }
    }
--- request
GET /lua
--- response_body
content phase executed
--- error_log
precontent phase executed
--- no_error_log
[error]



=== TEST 3: precontent_by_lua_block with ngx.exit(403)
--- config
    location /lua {
        precontent_by_lua_block {
            ngx.exit(403)
        }
        content_by_lua_block {
            ngx.say("content phase executed")
        }
    }
--- request
GET /lua
--- error_code: 403
--- no_error_log
[error]



=== TEST 4: precontent_by_lua_block accessing request body
--- config
    location /test {
        precontent_by_lua_block {
            ngx.req.read_body()
            local body = ngx.req.get_body_data()
            if body then
                ngx.log(ngx.INFO, "precontent got body: " .. body)
            end
        }
        content_by_lua_block {
            ngx.say("content phase")
        }
    }
--- request
POST /test
hello world
--- response_body
content phase
--- error_log
precontent got body: hello world
--- no_error_log
[error]



=== TEST 5: precontent_by_lua_block setting ctx for content phase
--- config
    location /lua {
        precontent_by_lua_block {
            ngx.ctx.precontent = "set in precontent"
        }
        content_by_lua_block {
            ngx.say("var from precontent: ", ngx.ctx.precontent or "nil")
        }
    }
--- request
GET /lua
--- response_body
var from precontent: set in precontent
--- no_error_log
[error]



=== TEST 6: precontent_by_lua_file
--- config
    location /lua {
        precontent_by_lua_file html/test.lua;
        content_by_lua_block {
            ngx.say("content phase")
        }
    }
--- user_files
>>> test.lua
ngx.log(ngx.INFO, "precontent_by_lua_file executed")
--- request
GET /lua
--- response_body
content phase
--- error_log
precontent_by_lua_file executed
--- no_error_log
[error]



=== TEST 7: precontent_by_lua_block with subrequests
--- config
    location /main {
        precontent_by_lua_block {
            ngx.log(ngx.INFO, "precontent phase - is_subrequest: ", ngx.is_subrequest)
        }
        content_by_lua_block {
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
        }
    }
    
    location /sub {
        content_by_lua_block {
            ngx.say("subrequest executed")
        }
    }
--- request
GET /main
--- response_body
subrequest executed
--- error_log
precontent phase - is_subrequest: false
--- no_error_log
[error]



=== TEST 8: precontent_by_lua_block getting phase name
--- config
    location /phase {
        precontent_by_lua_block {
            ngx.log(ngx.INFO, "current phase: ", ngx.get_phase())
        }
        content_by_lua_block {
            ngx.say("content phase")
        }
    }
--- request
GET /phase
--- response_body
content phase
--- error_log
current phase: precontent
--- no_error_log
[error]



=== TEST 9: precontent_by_lua_block with header manipulation
--- config
    location /header {
        precontent_by_lua_block {
            ngx.req.set_header("X-Precontent", "added-in-precontent")
        }
        content_by_lua_block {
            ngx.say("Header X-Precontent: ", ngx.var.http_x_precontent or "not found")
        }
    }
--- request
GET /header
--- response_body
Header X-Precontent: added-in-precontent
--- no_error_log
[error]



=== TEST 10: rewrite args
--- config
    location /args {
        precontent_by_lua_block {
            ngx.req.set_uri_args("modified=1&test=2")
        }
        content_by_lua_block {
            ngx.say("Args in content: ", ngx.var.args)
        }
    }
--- request
GET /args?original=1
--- response_body
Args in content: modified=1&test=2
--- no_error_log
[error]



=== TEST 11: syntax error in precontent_by_lua_block
--- config
    location /lua {

        precontent_by_lua_block {
            'for end';
        }
        content_by_lua_block {
            ngx.say("Hello world")
        }
    }
--- request
GET /lua
--- ignore_response
--- error_log
failed to load inlined Lua code: precontent_by_lua(nginx.conf:41):2: unexpected symbol near ''for end''
--- no_error_log
no_such_error
--- skip_eval: 2:$ENV{TEST_NGINX_USE_HUP}



=== TEST 12: precontent_by_lua_block directive in server
--- config
    precontent_by_lua_block {
        ngx.ctx.server_level_precontent = "executed"
    }
    location /inherit {
        content_by_lua_block {
            ngx.say("Server level precontent ran: ", ngx.ctx.server_level_precontent)
        }
    }
--- request
GET /inherit
--- response_body
Server level precontent ran: executed
--- no_error_log
[error]



=== TEST 13: precontent_by_lua_block overriding in location
--- config
    precontent_by_lua_block {
        ngx.ctx.server_level_precontent = "server_default"
    }
    location /override {
        precontent_by_lua_block {
            ngx.ctx.location_level_precontent = "location_specific"
        }
        content_by_lua_block {
            ngx.say("Server level: ", ngx.ctx.server_level_precontent or "not executed")
            ngx.say("Location level: ", ngx.ctx.location_level_precontent or "not executed")
        }
    }
--- request
GET /override
--- response_body
Server level: not executed
Location level: location_specific
--- no_error_log
[error]



=== TEST 14: sleep
--- config
    location /lua {
        precontent_by_lua_block {
            ngx.sleep(0.001)
            ngx.log(ngx.INFO, "precontent_by_lua_block executed")
        }
        content_by_lua_block {
            ngx.say("content phase executed")
        }
    }
--- request
GET /lua
--- response_body
content phase executed
--- error_log
precontent_by_lua_block executed
--- no_error_log
[error]



=== TEST 15: cosocket
--- config
    location /lua {
        precontent_by_lua_block {
            local sock, err = ngx.socket.tcp()
            if not sock then
                ngx.log(ngx.ERR, "Failed to create sock: ", err)
                return
            end

            local ok
            ok, err = sock:connect("127.0.0.1", ngx.var.server_port)
            if not ok then
                ngx.log(ngx.ERR, "Failed to connect to google: ", err)
            end
            sock:close()

            ngx.log(ngx.INFO, "precontent_by_lua_block executed")
        }
        content_by_lua_block {
            ngx.say("content phase executed")
        }
    }
--- request
GET /lua
--- response_body
content phase executed
--- error_log
precontent_by_lua_block executed
--- no_error_log
[error]
