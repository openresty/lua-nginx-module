# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => blocks() * repeat_each() * 2;

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /read {
        content_by_lua '
            local s = ndk.set_var.set_escape_uri(" :")
            local r = ndk.set_var.set_unescape_uri("a%20b")
            ngx.say(s)
            ngx.say(r)
        ';
    }
--- request
GET /read
--- response_body
%20%3a
a b



=== TEST 2: directive not found
--- config
    location /read {
        content_by_lua '
            local s = ndk.set_var.set_escape_uri_blah_blah(" :")
            ngx.say(s)
        ';
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 3: directive not found
--- config
    location /read {
        content_by_lua '
            local s = ndk.set_var.content_by_lua(" :")
            ngx.say(s)
        ';
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500

