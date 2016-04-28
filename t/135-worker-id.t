# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
master_on();
workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("worker id: ", ngx.worker.id())
        }
    }
--- request
GET /lua
--- response_body_like chop
^worker id: [0-1]$
--- no_error_log
[error]
--- skip_nginx: 3: <=1.9.0



=== TEST 2: worker id should be nil for non-worker processes
--- http_config
    proxy_buffering on;
    proxy_cache_valid any 10m;
    proxy_cache_path conf/cache levels=1:2 keys_zone=my-cache:8m max_size=1000m inactive=600m;
    proxy_temp_path conf/temp;
    proxy_buffer_size 4k;
    proxy_buffers 100 8k;
    init_worker_by_lua_block {
        ngx.log(ngx.ERR, "worker id ", ngx.worker.id());
    }
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("worker id: ", ngx.worker.id())
        }
    }
    location /cache {
        proxy_pass http://www.baidu.com;
        proxy_cache my-cache;
    }
--- request
GET /lua
--- response_body_like chop
^worker id: [0-1]$
--- grep_error_log eval: qr/worker id nil/
--- grep_error_log_out eval
[
"worker id nil\x{0a}worker id nil\n",
"",
]
--- skip_nginx: 3: <=1.9.0
