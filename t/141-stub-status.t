use Test::Nginx::Socket::Lua;

#master_on();
#workers(1);
#worker_connections(1014);
#log_level('warn');
#master_process_enabled(1);

repeat_each(2);

plan tests => repeat_each() * blocks() * 2;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_diff();
no_long_string();
#no_shuffle();

run_tests();

__DATA__

=== TEST 1: stub_status returns the expected table
--- config
    location /stub {
        content_by_lua_block {
            if not ngx.stub_status then
                ngx.say("disable")
                return
            else
                local stat = ngx.stub_status()
                if type(stat.active) ~= "number" then
                    ngx.say("failed")
                    return
                end
                if type(stat.accepted) ~= "number" then
                    ngx.say("failed")
                    return
                end
                if type(stat.handled) ~= "number" then
                    ngx.say("failed")
                    return
                end
                if type(stat.requests) ~= "number" then
                    ngx.say("failed")
                    return
                end
                if type(stat.reading) ~= "number" then
                    ngx.say("failed")
                    return
                end
                if type(stat.writing) ~= "number" then
                    ngx.say("failed")
                    return
                end
                if type(stat.waiting) ~= "number" then
                    ngx.say("failed")
                    return
                end
                ngx.say("succeed")
                return
        }
    }
--- request
GET /stub
--- response_body_like
succeed|disable
