# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => blocks() * repeat_each() * 2;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_CLIENT_PORT} ||= server_port();

my $pwd = `pwd`;
chomp $pwd;
$ENV{TEST_NGINX_PWD} ||= $pwd;

no_long_string();
run_tests();

__DATA__

=== TEST 1: lua-memcached
--- http_config
    lua_package_path '$TEST_NGINX_PWD/t/lib/?.lua;;';
--- config
    location /test {
        content_by_lua '
            package.loaded["socket"] = ngx.socket
            local Memcached = require "Memcached"
            Memcached.socket = ngx.socket

            local memc = Memcached.Connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)

            memc:set("some_key", "hello 1234")
            local data = memc:get("some_key")
            ngx.say("some_key: ", data)
        ';
    }
--- request
    GET /test
--- response_body
some_key: hello 1234

