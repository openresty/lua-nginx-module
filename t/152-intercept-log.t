# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('error');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 6);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- http_config
    lua_intercept_error_log 4m;
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.ERR, "enter 1")
            ngx.log(ngx.ERR, "enter 11")

            local t = ngx.get_log()
            ngx.say("log lines:", #t)
        }
    }
--- request
GET /t
--- response_body
log lines:2
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
--- skip_nginx: 3: <1.11.2



=== TEST 2: overflow intercepted error logs
--- http_config
    lua_intercept_error_log 4k;
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.ERR, "enter 1")
            ngx.log(ngx.ERR, "enter 22" .. string.rep("a", 4096))

            local t = ngx.get_log()
            ngx.say("log lines:", #t)
        }
    }
--- request
GET /t
--- response_body
log lines:1
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
--- skip_nginx: 3: <1.11.2



=== TEST 3: 404 error(not found)
--- http_config
    lua_intercept_error_log 4m;
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
intercept log line:1
$/,
qr/^No such file or directory
intercept log line:2
$/
]
--- skip_nginx: 2: <1.11.2



=== TEST 4: 500 error
--- http_config
    lua_intercept_error_log 4m;
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
intercept log line:1
$/,
qr/^attempt to perform arithmetic on a table value
intercept log line:2
$/
]
--- skip_nginx: 2: <1.11.2



=== TEST 5: no error log
--- http_config
    lua_intercept_error_log 4m;
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
qr/^intercept log line:1
$/
]
--- skip_nginx: 3: <1.11.2



=== TEST 6: customize the log path
--- http_config
    lua_intercept_error_log 4m;
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
intercept log line:1
$/,
qr/^enter access
intercept log line:2
$/
]
--- skip_nginx: 3: <1.11.2



=== TEST 7: invalid size (< 4k)
--- http_config
    lua_intercept_error_log 3k;
--- config
    location /t {
        echo "hello";
    }
--- must_die
--- error_log
invalid intercept error log size "3k", minimum size is 4KB
--- skip_nginx: 2: <1.11.2



=== TEST 8: invalid size (> 32m)
--- http_config
    lua_intercept_error_log 33m;
--- config
    location /t {
        echo "hello";
    }
--- must_die
--- error_log
invalid intercept error log size "33m", max size is 32MB
--- skip_nginx: 2: <1.11.2



=== TEST 9: invalid size (no argu)
--- http_config
    lua_intercept_error_log;
--- config
    location /t {
        echo "hello";
    }
--- must_die
--- error_log
invalid number of arguments in "lua_intercept_error_log" directive
--- skip_nginx: 2: <1.11.2



=== TEST 10: without directive
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.ERR, "enter 1")

            local t = ngx.get_log()
            ngx.say("log lines:", #t)
        }
    }
--- request
GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API "ngx.get_log" depends on directive "lua_intercept_error_log"
--- skip_nginx: 3: <1.11.2



=== TEST 11: without directive
--- config
    location /t {
        access_by_lua_block {
            ngx.filter_log(ngx.ERR)
        }
    }
--- request
GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API "ngx.filter_log" depends on directive "lua_intercept_error_log"
--- skip_nginx: 3: <1.11.2
