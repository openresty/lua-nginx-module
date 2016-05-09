# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
master_on();
workers(2);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 1);

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
    proxy_cache_path conf/cache levels=1:2 keys_zone=my-cache:8m max_size=10m inactive=60m;
    proxy_temp_path conf/temp;

    lua_shared_dict counters 1m;

    init_by_lua_block {
        ngx.shared.counters:set("c", 0)
    }

    init_worker_by_lua_block {
        ngx.shared.counters:incr("c", 1)
        ngx.log(ngx.INFO, ngx.worker.pid(), ": worker id ", ngx.worker.id());
    }
--- config
    location = /t {
        content_by_lua_block {
            local counters = ngx.shared.counters
            local ok, c
            for i = 1, 45 do
                c = counters:get("c")
                if c >= 4 then
                    ok = true
                    break
                end
                local delay = 0.001 * i
                if delay > 0.1 then
                    delay = 0.1
                end
                ngx.sleep(delay)
            end
            if ok then
                ngx.say("ok")
            else
                ngx.say("not ok: c=", c)
            end
        }
    }
    location /cache {
        proxy_pass http://127.0.0.1:$server_port;
        proxy_cache my-cache;
    }
--- request
GET /t
--- response_body
ok
--- grep_error_log eval: qr/worker id nil/
--- grep_error_log_out
worker id nil
worker id nil
--- no_error_log
[error]
--- wait: 0.1
--- skip_nginx: 3: <=1.9.0
--- log_level: info
--- timeout: 6
