# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();


#murmur32_bin is hard to test, so convert it to hex mode

__DATA__

=== TEST 1: set murmur32_bin hello ????xxoo
--- config
    location = /murmur32_bin {
        content_by_lua '
            local a = ngx.murmur32_bin("hello")
            ngx.say(a)
        ';
    }
--- request
GET /murmur32_bin
--- response_body
3848350155



=== TEST 2: set murmur32_bin hello ????xxoo
--- config
    location = /murmur32_bin {
        content_by_lua 'ngx.say(string.len(ngx.murmur32_bin("hello")))';
    }
--- request
GET /murmur32_bin
--- response_body
10



=== TEST 3: set murmur32_bin hello
--- config
    location = /murmur32_bin {
        content_by_lua '
            s = string.format("%08x", ngx.murmur32_bin("hello"))
            ngx.say(s)
        ';
    }
--- request
GET /murmur32_bin
--- response_body
e56129cb



=== TEST 4: nil string to ngx.murmur32_bin
--- config
    location = /murmur32_bin {
        content_by_lua '
            local s = ngx.murmur32_bin(nil)
            ngx.say(s)
        ';
    }
--- request
GET /murmur32_bin
--- response_body
0



=== TEST 5: null string to ngx.murmur32_bin
--- config
    location /murmur32_bin {
        content_by_lua '
            local s = ngx.murmur32_bin("")
            ngx.say(s)
        ';
    }
--- request
GET /murmur32_bin
--- response_body
0



=== TEST 6: use ngx.murmur32_bin in set_by_lua
--- config
    location = /murmur32_bin {
        set_by_lua $a 'return string.format("%08x", ngx.murmur32_bin("hello"))';
        echo $a;
    }
--- request
GET /murmur32_bin
--- response_body
e56129cb



=== TEST 7: use ngx.murmur32_bin in set_by_lua (nil)
--- config
    location = /murmur32_bin {
        set_by_lua $a 'return string.format("%08x", ngx.murmur32_bin(nil))';
        echo $a;
    }
--- request
GET /murmur32_bin
--- response_body
00000000



=== TEST 8: use ngx.murmur32_bin in set_by_lua (null string)
--- config
    location /murmur32_bin {
        set_by_lua $a 'return string.format("%08x", ngx.murmur32_bin(""))';
        echo $a;
    }
--- request
GET /murmur32_bin
--- response_body
00000000



=== TEST 9: murmur32_bin(number)
--- config
    location = /t {
        content_by_lua '
            s = string.format("%08x", ngx.murmur32_bin(45))
            ngx.say(s)
        ';
    }
--- request
GET /t
--- response_body
1951db0d
