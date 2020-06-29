# vi:ft=

use Test::Nginx::Socket::Lua;

plan tests => 2 * blocks();

no_long_string();

add_block_preprocessor(sub {
    my $block = shift;

    my $http_config = $block->http_config // '';

    $http_config .= <<_EOC_;

    lua_package_path "./lib/?.lua;../lua-tablepool/lib/?.lua;../lua-resty-signal/lib/?.lua;../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;../lua-resty-shell/lib/?.lua;;";
    lua_package_cpath "../lua-resty-signal/?.so;;";

_EOC_

    $block->set_value("http_config", $http_config);
});


run_tests();

__DATA__

=== TEST 1: SIGHUP follow by SIGQUIT
--- config
    location = /t {
        content_by_lua_block {
            local resty_signal = require "resty.signal"
            do
                local pid = ngx.worker.pid()

                resty_signal.kill(pid, "HUP")
                ngx.sleep(0.01)

                resty_signal.kill(pid, "QUIT")
            end
        }
    }
--- request
GET /t
--- ignore_response
--- wait: 0.1
--- error_log eval
qr/\[notice\] \d+#\d+: exit/
--- no_error_log eval
qr/\[notice\] \d+#\d+: reconfiguring/



=== TEST 2: exit after recv SIGHUP in single process mode
--- config
    location = /t {
        content_by_lua_block {
            local resty_signal = require "resty.signal"
            do
                local pid = ngx.worker.pid()

                resty_signal.kill(pid, "HUP")
            end

        }
    }
--- request
GET /t
--- ignore_response
--- wait: 0.1
--- error_log eval
qr/\[notice\] \d+#\d+: exit/
--- no_error_log eval
qr/\[notice\] \d+#\d+: reconfiguring/
