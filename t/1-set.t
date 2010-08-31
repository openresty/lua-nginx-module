# vi:ft=

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);
#repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

no_long_string();

run_tests();

__DATA__

=== TEST 1: simple set (integer)
--- config
    location /lua {
        set_by_lua $res "return 1+1";
        echo $res;
    }
--- request
GET /lua
--- response_body
2



=== TEST 2: simple set (string)
--- config
    location /lua {
        set_by_lua $res "return 'hello' .. 'world'";
        echo $res;
    }
--- request
GET /lua
--- response_body
helloworld



=== TEST 3: internal only
--- config
    location /lua {
        set_by_lua $res "function fib(n) if n > 2 then return fib(n-1)+fib(n-2) else return 1 end end return fib(10)";
        echo $res;
    }
--- request
GET /lua
--- response_body
55



=== TEST 4: internal script with argument
--- config
    location /lua {
        set_by_lua $res "return ngx.arg[1]+ngx.arg[2]" $arg_a $arg_b;
        echo $res;
    }
--- request
GET /lua?a=1&b=2
--- response_body
3



=== TEST 5: fib by arg
--- config
    location /fib {
        set_by_lua $res "function fib(n) if n > 2 then return fib(n-1)+fib(n-2) else return 1 end end return fib(tonumber(ngx.arg[1]))" $arg_n;
        echo $res;
    }
--- request
GET /fib?n=10
--- response_body
55



=== TEST 6: adder
--- config
    location = /adder {
        set_by_lua $res
            "local a = tonumber(ngx.arg[1])
             local b = tonumber(ngx.arg[2])
             return a + b" $arg_a $arg_b;

        echo $res;
    }
--- request
GET /adder?a=25&b=75
--- response_body
100



=== TEST 7: read nginx variables directly from within Lua
--- config
    location = /set-both {
        set $b 32;
        set_by_lua $a "return tonumber(ngx.var.b) + 1";

        echo "a = $a";
    }
--- request
GET /set-both
--- response_body
a = 33



=== TEST 8: set nginx variables directly from within Lua
--- config
    location = /set-both {
        set $b "";
        set_by_lua $a "ngx.var.b = 32; return 7";

        echo "a = $a";
        echo "b = $b";
    }
--- request
GET /set-both
--- response_body
a = 7
b = 32



=== TEST 9: set non-existent nginx variables
--- config
    location = /set-both {
        #set $b "";
        set_by_lua $a "ngx.var.b = 32; return 7";

        echo "a = $a";
    }
--- request
GET /set-both
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 10: use dollar in inline lua
--- config
    location = /set {
        set $a 12;
        set_by_lua $a "return 'x$$x'";
        echo "a = $a";
    }
--- request
GET /set
--- response_body
a = x$$x
