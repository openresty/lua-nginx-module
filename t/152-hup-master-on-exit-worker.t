# vim:set ft= ts=4 sw=4 et fdm=marker:

our $SkipReason;

BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

no_long_string();

master_on();

run_tests();

__DATA__

=== TEST 1: exit_worker_by_lua_block reload
--- http_config
    exit_worker_by_lua_block {
        ngx.log(ngx.NOTICE, "log from exit_worker_by_lua_block")
    }
--- config
    location /t {
        echo "ok";
    }
--- request
GET /t
--- response_body
ok
--- shutdown_error_log
log from exit_worker_by_lua_block

