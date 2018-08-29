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

__DATA__

=== TEST 1: set murmur32 hello
--- config
    location = /murmur32 {
        content_by_lua 'ngx.say(ngx.murmur32("hello"))';
    }
--- request
GET /murmur32
--- response_body
3848350155



=== TEST 2: nil string to ngx.murmur32
--- config
    location = /murmur32 {
        content_by_lua 'ngx.say(ngx.murmur32(nil))';
    }
--- request
GET /murmur32
--- response_body
0



=== TEST 3: null string to ngx.murmur32
--- config
    location /murmur32 {
        content_by_lua 'ngx.say(ngx.murmur32(""))';
    }
--- request
GET /murmur32
--- response_body
0



=== TEST 4: use ngx.murmur32 in set_by_lua
--- config
    location = /murmur32 {
        set_by_lua $a 'return ngx.murmur32("hello")';
        echo $a;
    }
--- request
GET /murmur32
--- response_body
3848350155



=== TEST 5: use ngx.murmur32 in set_by_lua (nil)
--- config
    location = /murmur32 {
        set_by_lua $a 'return ngx.murmur32(nil)';
        echo $a;
    }
--- request
GET /murmur32
--- response_body
0



=== TEST 6: use ngx.murmur32 in set_by_lua (null string)
--- config
    location /murmur32 {
        set_by_lua $a 'return ngx.murmur32("")';
        echo $a;
    }
--- request
GET /murmur32
--- response_body
0



=== TEST 7: murmur32(number)
--- config
    location = /murmur32 {
        content_by_lua 'ngx.say(ngx.murmur32(45))';
    }
--- request
GET /murmur32
--- response_body
424794893
