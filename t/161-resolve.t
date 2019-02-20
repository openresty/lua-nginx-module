# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua 'no_plan';

#worker_connections(1014);
#master_process_enabled(1);

no_long_string();
run_tests();

__DATA__


=== TEST 1: use ngx.resolve in rewrite_by_lua_block
--- config
    resolver 8.8.8.8;
    rewrite_by_lua "ngx.ctx.addr = ngx.resolve('google.com')";
    location = /resolve {
        content_by_lua "ngx.say(ngx.ctx.addr)";
    }
--- request
GET /resolve
--- response_body_like: ^\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}$



=== TEST 2: use ngx.resolve in access_by_lua_block
--- config
    resolver 8.8.8.8;
    access_by_lua "ngx.ctx.addr = ngx.resolve('google.com')";
    location = /resolve {
        content_by_lua "ngx.say(ngx.ctx.addr)";
    }
--- request
GET /resolve
--- response_body_like: ^\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}$



=== TEST 3: use ngx.resolve in content_by_lua_block
--- config
    resolver 8.8.8.8;
    location = /resolve {
        content_by_lua "ngx.say(ngx.resolve('google.com'))";
    }
--- request
GET /resolve
--- response_body_like: ^\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}$



=== TEST 4: query only IPv6 addresses
--- config
    resolver 8.8.8.8;
    location = /resolve {
        content_by_lua "ngx.say(ngx.resolve('google.com', { ipv4 = false, ipv6 = true }))";
    }
--- request
GET /resolve
--- response_body_like: ^[a-fA-F0-9:]+$



=== TEST 5: pass IPv4 address to ngx.resolve
--- config
    location = /resolve {
        content_by_lua "ngx.say(ngx.resolve('192.168.0.1'))";
    }
--- request
GET /resolve
--- response_body
192.168.0.1



=== TEST 6: pass IPv6 address to ngx.resolve
--- config
    location = /resolve {
        content_by_lua "ngx.say(ngx.resolve('[2a00:1450:4010:c05::66]'))";
    }
--- request
GET /resolve
--- response_body
2a00:1450:4010:c05::66



=== TEST 7: pass non-existent domain name to ngx.resolve
--- config
    resolver 8.8.8.8;
    resolver_timeout 1s;
    location = /resolve {
        content_by_lua "ngx.say(ngx.resolve('non-existent-domain-name'))";
    }
--- request
GET /resolve
--- response_body
niladdress not found
