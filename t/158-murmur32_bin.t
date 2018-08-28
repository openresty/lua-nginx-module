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
        content_by_lua 'local a = string.gsub(ngx.murmur32_bin("hello"), ".", function (c)
                    return string.format("%ud", string.byte(c))
                end); ngx.say(a)';
    }
--- request
GET /murmur32_bin
--- response_body
5d41402abc4b2a76b9719d911017c592



=== TEST 2: set murmur32_bin hello ????xxoo
--- config
    location = /murmur32_bin {
        content_by_lua 'ngx.say(string.len(ngx.murmur32_bin("hello")))';
    }
--- request
GET /murmur32_bin
--- response_body
16



=== TEST 3: set murmur32_bin hello
--- config
    location = /murmur32_bin {
        content_by_lua '
            local s = ngx.murmur32_bin("hello")
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            ngx.say(s)
        ';
    }
--- request
GET /murmur32_bin
--- response_body
5d41402abc4b2a76b9719d911017c592



=== TEST 4: nil string to ngx.murmur32_bin
--- config
    location = /murmur32_bin {
        content_by_lua '
            local s = ngx.murmur32_bin(nil)
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            ngx.say(s)
        ';
    }
--- request
GET /murmur32_bin
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 5: null string to ngx.murmur32_bin
--- config
    location /murmur32_bin {
        content_by_lua '
            local s = ngx.murmur32_bin("")
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            ngx.say(s)
        ';
    }
--- request
GET /murmur32_bin
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 6: use ngx.murmur32_bin in set_by_lua
--- config
    location = /murmur32_bin {
        set_by_lua $a 'return string.gsub(ngx.murmur32_bin("hello"), ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)';
        echo $a;
    }
--- request
GET /murmur32_bin
--- response_body
5d41402abc4b2a76b9719d911017c592



=== TEST 7: use ngx.murmur32_bin in set_by_lua (nil)
--- config
    location = /murmur32_bin {
        set_by_lua $a '
            local s = ngx.murmur32_bin(nil)
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            return s
        ';
        echo $a;
    }
--- request
GET /murmur32_bin
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 8: use ngx.murmur32_bin in set_by_lua (null string)
--- config
    location /murmur32_bin {
        set_by_lua $a '
            local s = ngx.murmur32_bin("")
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            return s
        ';
        echo $a;
    }
--- request
GET /murmur32_bin
--- response_body
d41d8cd98f00b204e9800998ecf8427e



=== TEST 9: murmur32_bin(number)
--- config
    location = /t {
        content_by_lua '
            s = ngx.murmur32_bin(45)
            s = string.gsub(s, ".", function (c)
                    return string.format("%02x", string.byte(c))
                end)
            ngx.say(s)

        ';
    }
--- request
GET /t
--- response_body
6c8349cc7260ae62e3b1396831a8398f
