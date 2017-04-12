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
    lua_intercept_log 4m;
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.ERR, "enter 1")
            ngx.log(ngx.ERR, "enter 11")

            local t = ngx.get_log()
            ngx.say("log length:", #t)
        }
    }
--- request
GET /t
--- response_body
log length:341
--- grep_error_log eval
qr/enter \d+/
--- grep_error_log_out eval
[
"enter 1
enter 11
",
"enter 1
enter 11
"
]



=== TEST 2: overflow intercepted error logs
--- http_config
    lua_intercept_log 256;
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.ERR, "enter 1")
            ngx.log(ngx.ERR, "enter 22")

            local t = ngx.get_log()
            ngx.say("log length:", #t)
        }
    }
--- request
GET /t
--- response_body
log length:170
--- grep_error_log eval
qr/enter \d+/
--- grep_error_log_out eval
[
"enter 1
enter 22
",
"enter 1
enter 22
"
]



=== TEST 3: 404 error(not found)
--- http_config
    lua_intercept_log 4m;
--- config
    log_by_lua_block {
        local t = ngx.get_log()
        ngx.log(ngx.ERR, "intercept log line:", #t)
    }
--- request
GET /t
--- error_code: 404
--- grep_error_log eval
qr/intercept log line:\d+|No such file or directory/
--- grep_error_log_out eval
[
qr/^No such file or directory
intercept log line:2\d{2}
$/,
qr/^No such file or directory
intercept log line:4\d{2}
$/
]



=== TEST 4: 500 error
--- http_config
    lua_intercept_log 4m;
--- config
    location /t {
        content_by_lua_block {
            local t = {}/4
        }
    }
    log_by_lua_block {
        local t = ngx.get_log()
        ngx.log(ngx.ERR, "intercept log line:", #t)
    }
--- request
GET /t
--- error_code: 500
--- grep_error_log eval
qr/intercept log line:\d+|attempt to perform arithmetic on a table value/
--- grep_error_log_out eval
[
qr/^attempt to perform arithmetic on a table value
intercept log line:3\d{2}
$/,
qr/^attempt to perform arithmetic on a table value
intercept log line:5\d{2}
$/
]



=== TEST 5: no error log
--- http_config
    lua_intercept_log 4m;
--- config
    location /t {
        echo "hello";
    }
    log_by_lua_block {
        local t = ngx.get_log()
        ngx.log(ngx.ERR, "intercept log line:", #t)
    }
--- request
GET /t
--- response_body
hello
--- grep_error_log eval
qr/intercept log line:\d+/
--- grep_error_log_out eval
[
qr/^intercept log line:0
$/,
qr/^intercept log line:2\d{2}
$/
]



=== TEST 6: customize the log path
--- http_config
    lua_intercept_log 4m;
    error_log logs/error_http.log error;
--- config
    location /t {
        error_log logs/error.log error;
        access_by_lua_block {
            ngx.log(ngx.ERR, "enter access /t")
        }
        echo "hello";
    }
    log_by_lua_block {
        local t = ngx.get_log()
        ngx.log(ngx.ERR, "intercept log line:", #t)

    }
--- request
GET /t
--- response_body
hello
--- grep_error_log eval
qr/intercept log line:\d+|enter access/
--- grep_error_log_out eval
[
qr/^enter access
intercept log line:1\d{2}
$/,
qr/^enter access
intercept log line:3\d{2}
$/
]
