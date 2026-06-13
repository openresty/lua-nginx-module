# vim:set ft= ts=4 sw=4 et fdm=marker:
#
# Test for HTTP/2 subrequest wakeup issue when parent request times out
# Bug: When an HTTP/2 parent request times out while waiting for a subrequest,
# the parent's error_wakeup() could incorrectly try to wake up the still-running
# subrequest, causing undefined behavior.
#
# Reproduction: timeout 2 curl -i --http2 -k https://localhost:8443/delay/5
# The parent times out after 2s but the subrequest is still sleeping for 5s.

use Test::Nginx::Socket::Lua;
use Cwd qw(abs_path realpath);
use File::Basename;
use File::Path qw(rmtree);

log_level('info');

my $nginx = $ENV{TEST_NGINX_BINARY} || 'nginx';
my $nginx_v = eval { `$nginx -V 2>&1` } // '';
our $HasHttpSlice = $nginx_v =~ /--with-http_slice_module/;

repeat_each(2);

plan tests => repeat_each() * 48;

#no_diff();
no_shuffle();
no_long_string();

my $slice_cache_dir = "/tmp/lua-nginx-module-slice-cache-" . server_port();
rmtree($slice_cache_dir);
add_cleanup_handler(sub { rmtree($slice_cache_dir) });

run_tests();

__DATA__

=== TEST 1: HTTP/2 parent request timeout during subrequest sleep
--- config
    location /delay {
        content_by_lua_block {
            ngx.log(ngx.INFO, "Parent request started, issuing subrequest with 3s delay")
            local res = ngx.location.capture("/sub_delay")
            ngx.log(ngx.INFO, "Parent request finished, got response from subrequest")
            ngx.say("parent: ", res.body)
        }
    }

    location /sub_delay {
        content_by_lua_block {
            ngx.log(ngx.INFO, "Subrequest started, sleeping for 3 seconds")
            ngx.sleep(3)
            ngx.log(ngx.INFO, "Subrequest woke up after 3 seconds")
            ngx.say("subreq completed after 3s delay")
        }
    }
--- http2
--- request
GET /delay
--- timeout: 1
--- abort
--- ignore_response
--- curl_error: (28) Operation timed out
--- error_log
Parent request started, issuing subrequest with 3s delay
Subrequest started, sleeping for 3 seconds
--- shutdown_error_log
Subrequest woke up after 3 seconds
Parent request finished, got response from subrequest
--- no_error_log
[alert]
[crit]
[emerg]
[error]
--- no_shutdown_error_log
[alert]
[crit]
[emerg]
[error]



=== TEST 2: HTTP/2 nested subrequests with parent timeout
--- config
    location /outer {
        content_by_lua_block {
            ngx.log(ngx.INFO, "Outer request started")
            local res = ngx.location.capture("/middle")
            ngx.log(ngx.INFO, "Outer request completed")
            ngx.say("outer: ", res.body)
        }
    }

    location /middle {
        content_by_lua_block {
            ngx.log(ngx.INFO, "Middle subrequest started")
            local res = ngx.location.capture("/inner")
            ngx.log(ngx.INFO, "Middle subrequest completed")
            ngx.say("middle: ", res.body)
        }
    }

    location /inner {
        content_by_lua_block {
            ngx.log(ngx.INFO, "Inner subrequest started, sleeping 3s")
            ngx.sleep(3)
            ngx.log(ngx.INFO, "Inner subrequest woke up")
            ngx.say("inner done")
        }
    }
--- http2
--- request
GET /outer
--- timeout: 1
--- abort
--- ignore_response
--- curl_error: (28) Operation timed out
--- error_log
Outer request started
Middle subrequest started
Inner subrequest started, sleeping 3s
--- shutdown_error_log
Inner subrequest woke up
Middle subrequest completed
Outer request completed
--- no_error_log
[alert]
[crit]
[emerg]
[error]
--- no_shutdown_error_log
[alert]
[crit]
[emerg]
[error]



=== TEST 3: HTTP/2 parallel subrequests with parent timeout
--- config
    location /parallel {
        content_by_lua_block {
            ngx.log(ngx.INFO, "Starting parallel subrequests")
            local res1, res2 = ngx.location.capture_multi({
                {"/slow1"},
                {"/slow2"}
            })
            ngx.log(ngx.INFO, "Parallel subrequests completed")
            ngx.say("parallel done: ", res1.body, ", ", res2.body)
        }
    }

    location /slow1 {
        content_by_lua_block {
            ngx.log(ngx.INFO, "Subrequest slow1 sleeping 3s")
            ngx.sleep(3)
            ngx.log(ngx.INFO, "Subrequest slow1 finished")
            ngx.say("slow1 done")
        }
    }

    location /slow2 {
        content_by_lua_block {
            ngx.log(ngx.INFO, "Subrequest slow2 sleeping 3s")
            ngx.sleep(3)
            ngx.log(ngx.INFO, "Subrequest slow2 finished")
            ngx.say("slow2 done")
        }
    }

--- http2
--- request
GET /parallel
--- timeout: 1
--- abort
--- ignore_response
--- curl_error: (28) Operation timed out
--- error_log
Starting parallel subrequests
Subrequest slow1 sleeping 3s
Subrequest slow2 sleeping 3s
--- shutdown_error_log
Subrequest slow1 finished
Subrequest slow2 finished
Parallel subrequests completed
--- no_error_log
[alert]
[crit]
[emerg]
[error]
--- no_shutdown_error_log
[alert]
[crit]
[emerg]
[error]



=== TEST 4: HTTP/2 short subrequest completes before timeout
--- config
    location /fast {
        content_by_lua_block {
            ngx.log(ngx.INFO, "Fast parent started")
            local res = ngx.location.capture("/fast_sub")
            ngx.log(ngx.INFO, "Fast parent completed")
            ngx.print("result: ", res.body)
        }
    }

    location /fast_sub {
        content_by_lua_block {
            ngx.log(ngx.INFO, "Fast subrequest, sleeping 0.1s")
            ngx.sleep(0.1)
            ngx.log(ngx.INFO, "Fast subrequest finished")
            ngx.print("fast done")
        }
    }

--- http2
--- request
GET /fast
--- response_body chomp
result: fast done
--- error_log
Fast parent started
Fast subrequest, sleeping 0.1s
Fast subrequest finished
Fast parent completed
--- no_error_log
[alert]
[crit]
[emerg]
[error]
--- no_shutdown_error_log
[alert]
[crit]
[emerg]
[error]



=== TEST 5: warm slice cache for HTTP/2 slow client
--- skip_eval: 4: !$::HasHttpSlice
--- http_config
    send_timeout 5s;
    proxy_cache_path /tmp/lua-nginx-module-slice-cache-$TEST_NGINX_SERVER_PORT levels=1:2 keys_zone=SLICES:10m inactive=10m max_size=20m;

--- user_files eval
">>> origin/big.bin\n" . ("x" x (10 * 1024 * 1024))

--- config
    location = /slice-big.bin {
        slice 1m;
        proxy_cache SLICES;
        proxy_cache_key "$uri $slice_range";
        proxy_set_header Range $slice_range;
        proxy_cache_valid 200 206 1h;
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/origin/big.bin;
    }

    location /origin/ {
        root $TEST_NGINX_SERVER_ROOT/html;
    }

--- http2
--- request
GET /slice-big.bin
--- ignore_response
--- no_error_log
[alert]
[crit]
[emerg]
[error]
--- no_shutdown_error_log
[alert]
[crit]
[emerg]
[error]



=== TEST 6: HTTP/2 slow client with warmed slice cache
--- skip_eval: 4: !$::HasHttpSlice
--- http_config
    send_timeout 5s;
    proxy_cache_path /tmp/lua-nginx-module-slice-cache-$TEST_NGINX_SERVER_PORT levels=1:2 keys_zone=SLICES:10m inactive=10m max_size=20m;

--- user_files eval
">>> origin/big.bin\n" . ("x" x (10 * 1024 * 1024)) . "\n" .
">>> curl-slow.conf\n" .
"limit-rate = \"50k\"\n" .
"max-time = 8\n" .
"output = \"/dev/null\"\n"

--- config
    location = /slice-big.bin {
        slice 1m;
        proxy_cache SLICES;
        proxy_cache_key "$uri $slice_range";
        proxy_set_header Range $slice_range;
        proxy_cache_valid 200 206 1h;
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/origin/big.bin;
    }

    location /origin/ {
        root $TEST_NGINX_SERVER_ROOT/html;
    }

--- http2
--- request
GET /slice-big.bin
--- timeout: 12
--- ignore_response
--- curl_options: --config=t/servroot/html/curl-slow.conf
--- curl_error eval: qr/\((28|92)\)/
--- wait: 6
--- no_error_log
[alert]
[crit]
[emerg]
[error]
--- no_shutdown_error_log
[alert]
[crit]
[emerg]
[error]
