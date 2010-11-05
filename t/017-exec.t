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
            ngx.exec("/hi");
            ngx.say("Hi");
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body
Hello



=== TEST 2: empty uri arg
--- config
    location /read {
        content_by_lua '
            ngx.exec("");
            ngx.say("Hi");
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 3: no arg
--- config
    location /read {
        content_by_lua '
            ngx.exec();
            ngx.say("Hi");
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 4: too many args
--- config
    location /read {
        content_by_lua '
            ngx.exec(1, 2, 3, 4);
            ngx.say("Hi");
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 5: null uri
--- config
    location /read {
        content_by_lua '
            ngx.exec(nil)
            ngx.say("Hi")
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 6: user args
--- config
    location /read {
        content_by_lua '
            ngx.exec("/hi", "Yichun Zhang")
            ngx.say("Hi")
        ';
    }
    location /hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello Yichun Zhang



=== TEST 7: args in uri
--- config
    location /read {
        content_by_lua '
            ngx.exec("/hi?agentzh")
            ngx.say("Hi")
        ';
    }
    location /hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello agentzh



=== TEST 8: args in uri and user args
--- config
    location /read {
        content_by_lua '
            ngx.exec("/hi?a=Yichun", "b=Zhang")
            ngx.say("Hi")
        ';
    }
    location /hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello a=Yichun&b=Zhang



=== TEST 9: args in uri and user args
--- config
    location /read {
        content_by_lua '
            ngx.exec("@hi?a=Yichun", "b=Zhang")
            ngx.say("Hi")
        ';
    }
    location @hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello 

