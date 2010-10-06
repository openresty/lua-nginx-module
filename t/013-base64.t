# vim:set ft=perl ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();


__DATA__

=== TEST 1: base64 encode hello
--- config
    location = /base64_encode {
        content_by_lua 'ngx.say(ngx.base64_encode("hello"))';
    }
--- request
GET /base64_encode
--- response_body
aGVsbG8=


=== TEST 2: nil string to ngx.base64_encode
--- config
    location = /base64_encode {
        content_by_lua 'ngx.say("left" .. ngx.base64_encode(nil) .. "right")';
    }
--- request
GET /base64_encode
--- response_body
leftright



=== TEST 3: null string to ngx.base64_encode
--- config
    location = /base64_encode {
        content_by_lua 'ngx.say("left" .. ngx.base64_encode("") .. "right")';
    }
--- request
GET /base64_encode
--- response_body
leftright



=== TEST 4: use ngx.base64_encode in set_by_lua
--- config
    location = /base64_encode {
        set_by_lua $a 'return ngx.base64_encode("hello")';
        echo $a;
    }
--- request
GET /base64_encode
--- response_body
aGVsbG8=



=== TEST 5: use ngx.base64_encode in set_by_lua (nil)
--- config
    location = /base64_encode {
        set_by_lua $a 'return "left" .. ngx.base64_encode(nil) .. "right"';
        echo $a;
    }
--- request
GET /base64_encode
--- response_body
leftright



=== TEST 6: use ngx.base64_encode in set_by_lua (null string)
--- config
    location /base64_encode {
        set_by_lua $a 'return "left" .. ngx.base64_encode("") .. "right"';
        echo $a;
    }
--- request
GET /base64_encode
--- response_body
leftright



=== TEST 1: base64 encode hello
--- config
    location = /base64_decode {
        content_by_lua 'ngx.say(ngx.base64_decode("aGVsbG8="))';
    }
--- request
GET /base64_decode
--- response_body
hello


=== TEST 2: nil string to ngx.base64_decode
--- config
    location = /base64_decode {
        content_by_lua 'ngx.say("left" .. ngx.base64_decode(nil) .. "right")';
    }
--- request
GET /base64_decode
--- response_body
leftright



=== TEST 3: null string to ngx.base64_decode
--- config
    location = /base64_decode {
        content_by_lua 'ngx.say("left" .. ngx.base64_decode("") .. "right")';
    }
--- request
GET /base64_decode
--- response_body
leftright



=== TEST 4: use ngx.base64_decode in set_by_lua
--- config
    location = /base64_decode {
        set_by_lua $a 'return ngx.base64_decode("aGVsbG8=")';
        echo $a;
    }
--- request
GET /base64_decode
--- response_body
hello



=== TEST 5: use ngx.base64_decode in set_by_lua (nil)
--- config
    location = /base64_decode {
        set_by_lua $a 'return "left" .. ngx.base64_decode(nil) .. "right"';
        echo $a;
    }
--- request
GET /base64_decode
--- response_body
leftright



=== TEST 6: use ngx.base64_decode in set_by_lua (null string)
--- config
    location /base64_decode {
        set_by_lua $a 'return "left" .. ngx.base64_decode("") .. "right"';
        echo $a;
    }
--- request
GET /base64_decode
--- response_body
leftright

