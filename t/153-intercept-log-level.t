# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('info');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: log level(ngx.INFO)
--- http_config
    lua_intercept_error_log 4m;

    init_worker_by_lua_block {
        ngx.filter_log(ngx.INFO);
    }
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.INFO, "-->1")
            ngx.log(ngx.WARN, "-->2")
            ngx.log(ngx.ERR, "-->3")
        }
        content_by_lua_block {
            local log = ngx.get_log()
            ngx.say("log lines:", #log)
        }
    }
--- request
GET /t
--- response_body
log lines:3
--- grep_error_log eval
qr/-->\d+/
--- grep_error_log_out eval
[
"-->1
-->2
-->3
",
"-->1
-->2
-->3
"
]
--- skip_nginx: 3: <1.11.2



=== TEST 2: log level(ngx.WARN)
--- http_config
    lua_intercept_error_log 4m;

    init_worker_by_lua_block {
        ngx.filter_log(ngx.WARN);
    }
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.INFO, "-->1")
            ngx.log(ngx.WARN, "-->2")
            ngx.log(ngx.ERR, "-->3")
        }
        content_by_lua_block {
            local log = ngx.get_log()
            ngx.say("log lines:", #log)
        }
    }
--- request
GET /t
--- response_body
log lines:2
--- grep_error_log eval
qr/-->\d+/
--- grep_error_log_out eval
[
"-->1
-->2
-->3
",
"-->1
-->2
-->3
"
]
--- skip_nginx: 3: <1.11.2



=== TEST 3: log level(ngx.CRIT)
--- http_config
    lua_intercept_error_log 4m;

    init_worker_by_lua_block {
        ngx.filter_log(ngx.CRIT);
    }
--- config
    location /t {
        access_by_lua_block {
            ngx.log(ngx.INFO, "-->1")
            ngx.log(ngx.WARN, "-->2")
            ngx.log(ngx.ERR, "-->3")
        }
        content_by_lua_block {
            local log = ngx.get_log()
            ngx.say("log lines:", #log)
        }
    }
--- request
GET /t
--- response_body
log lines:0
--- grep_error_log eval
qr/-->\d+/
--- grep_error_log_out eval
[
"-->1
-->2
-->3
",
"-->1
-->2
-->3
"
]
--- skip_nginx: 3: <1.11.2
