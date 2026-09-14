# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

worker_connections(128);
log_level('info');
repeat_each(1);

plan tests => repeat_each() * (blocks() * 6 - 1);

my $pwd = cwd();

no_long_string();
no_shuffle();

check_accum_error_log();
run_tests();

__DATA__

=== TEST 1: sanity
--- http_config
    lua_shared_dict request_counter 1m;
    upstream my_upstream {
        server 127.0.0.1;
        balancer_by_lua_block {
            local balancer = require "ngx.balancer"

            if not ngx.ctx.tries then
                ngx.ctx.tries = 0
            end

            ngx.ctx.tries = ngx.ctx.tries + 1
            ngx.log(ngx.INFO, "tries ", ngx.ctx.tries)

            if ngx.ctx.tries == 1 then
                balancer.set_more_tries(5)
            end

            local host = "127.0.0.1"
            local port = $TEST_NGINX_RAND_PORT_1;

            local ok, err = balancer.set_current_peer(host, port)
            if not ok then
                ngx.log(ngx.ERR, "failed to set the current peer: ", err)
                return ngx.exit(500)
            end

            balancer.set_timeouts(60000, 60000, 60000)

            local ok, err = balancer.enable_keepalive(60, 100)
            if not ok then
                ngx.log(ngx.ERR, "failed to enable keepalive: ", err)
                return ngx.exit(500)
            end
        }
    }

    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1;
        location /hello {
            content_by_lua_block{
                local request_counter = ngx.shared.request_counter
                local first_request = request_counter:get("first_request")
                if first_request == nil then
                    request_counter:set("first_request", "yes")
                    ngx.print("hello")
                else
                    ngx.exit(ngx.HTTP_CLOSE)
                end
            }
        }
    }
--- config
    location = /t {
        proxy_pass http://my_upstream;
        proxy_set_header Connection "keep-alive";

        rewrite_by_lua_block {
           ngx.req.set_uri("/hello")
        }
    }
--- pipelined_requests eval
["GET /t HTTP/1.1" , "GET /t HTTP/1.1"]
--- response_body eval
["hello", qr/502/]
--- error_code eval
[200, 502]
--- no_error_log eval
qr/tries 7/



=== TEST 2: set_more_tries does not wrap after cached connection errors
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";
    lua_shared_dict warm_counter 1m;

    proxy_next_upstream_tries 3;
    upstream backend {
        server 0.0.0.1;
        keepalive 32;
        balancer_by_lua_block {
            local b = require "ngx.balancer"
            local n = (ngx.ctx.n or 0) + 1
            ngx.ctx.n = n
            ngx.log(ngx.INFO, "balancer ", ngx.var.uri, " invocation ", n)

            -- This is the pattern used by ingress-nginx: grant one extra
            -- attempt every time the balancer is entered, including retries.
            if n > 20 then
                ngx.log(ngx.ERR, "retry storm guard")
                return ngx.exit(500)
            end

            local ok, err = b.set_more_tries(1)
            if err then
                ngx.log(ngx.WARN, "set_more_tries: ", err)
            end

            assert(b.set_current_peer("127.0.0.1", $TEST_NGINX_RAND_PORT_1))
        }
    }

    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1;

        location = /warm {
            content_by_lua_block {
                local counter = ngx.shared.warm_counter
                local n = counter:incr("requests", 1, 0)
                while n < 32 do
                    ngx.sleep(0.01)
                    n = counter:get("requests")
                end
                ngx.say("ok")
            }
        }

        location / {
            return 444;
        }
    }
--- config
    location = /warm {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }

    location = /bad {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_next_upstream error timeout;
    }
--- init
use IO::Socket::INET;
use POSIX qw(_exit);

my @pids;
for (1 .. 32) {
    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        my $sock;
        for (1 .. 20) {
            $sock = IO::Socket::INET->new(
                PeerAddr => "127.0.0.1",
                PeerPort => $Test::Nginx::Util::ServerPort,
                Proto    => "tcp",
                Timeout  => 1,
            );
            last if $sock;
            select undef, undef, undef, 0.1;
        }

        _exit(1) unless $sock;
        $sock->autoflush(1);
        print $sock "GET /warm HTTP/1.1\r\n"
                    . "Host: localhost\r\n"
                    . "Connection: keep-alive\r\n\r\n";
        sysread($sock, my $buf, 4096);
        close $sock;
        _exit(0);
    }

    push @pids, $pid;
}

for my $pid (@pids) {
    waitpid($pid, 0);
    die "warm-up request failed" if $? != 0;
}
--- request
GET /bad
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- grep_error_log eval: qr/balancer \/bad invocation [123]/
--- grep_error_log_out
balancer /bad invocation 1
balancer /bad invocation 2
balancer /bad invocation 3
--- no_error_log
retry storm guard
[alert]
