# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('error');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 - 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- http_config
    lua_intercept_log 4;
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.ERR, "enter 1")
            ngx.log(ngx.ERR, "enter 2")
            ngx.say("hello")
        }
        log_by_lua_block {
            local t = ngx.req.get_intercept_log()
            ngx.log(ngx.ERR, "intercept log line:", #t)
        }
    }
--- request
GET /t
--- response_body
hello
--- grep_error_log eval
qr/enter \d|intercept log line:\d/
--- grep_error_log_out eval
[
"enter 1
enter 2
intercept log line:2
",
"enter 1
enter 2
intercept log line:2
"
]




=== TEST 2: maximum intercepted 3 error logs
--- http_config
    lua_intercept_log 3;
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.ERR, "enter 1")
            ngx.log(ngx.ERR, "enter 2")
            ngx.log(ngx.ERR, "enter 3")
            ngx.log(ngx.ERR, "enter 4")
            ngx.say("hello")
        }
        log_by_lua_block {
            local t = ngx.req.get_intercept_log()
            ngx.log(ngx.ERR, "intercept log line:", #t)
        }
    }
--- request
GET /t
--- response_body
hello
--- grep_error_log eval
qr/enter \d|intercept log line:\d/
--- grep_error_log_out eval
[
"enter 1
enter 2
enter 3
enter 4
intercept log line:3
",
"enter 1
enter 2
enter 3
enter 4
intercept log line:3
"
]



=== TEST 3: 404 error(not found)
--- http_config
    lua_intercept_log 4;
--- config
    log_by_lua_block {
        local t = ngx.req.get_intercept_log()
        ngx.log(ngx.ERR, "intercept log line:", #t)
        ngx.log(ngx.ERR, "------->:", t[1])
    }
--- request
GET /t
--- error_code: 404
--- grep_error_log eval
qr/intercept log line:1|No such file or directory/
--- grep_error_log_out eval
[
"No such file or directory
intercept log line:1
No such file or directory
",
"No such file or directory
intercept log line:1
No such file or directory
"
]



=== TEST 4: 500 error
--- http_config
    lua_intercept_log 4;
--- config
    location /t {
        content_by_lua_block {
            local t = {}/4
        }
    }
    log_by_lua_block {
        local t = ngx.req.get_intercept_log()
        ngx.log(ngx.ERR, "intercept log line:", #t)
        ngx.log(ngx.ERR, "------->:", t[1])
    }
--- request
GET /t
--- error_code: 500
--- grep_error_log eval
qr/intercept log line:1|attempt to perform arithmetic on a table value/
--- grep_error_log_out eval
[
"attempt to perform arithmetic on a table value
intercept log line:1
attempt to perform arithmetic on a table value
",
"attempt to perform arithmetic on a table value
intercept log line:1
attempt to perform arithmetic on a table value
"
]
