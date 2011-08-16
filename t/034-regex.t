# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+)")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
1234



=== TEST 2: single capture
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]{2})[0-9]+")
            if m then
                ngx.say(m[0])
                ngx.say(m[1])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
1234
12



=== TEST 3: multiple captures
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([a-z]+).*?([0-9]{2})[0-9]+")
            if m then
                ngx.say(m[0])
                ngx.say(m[1])
                ngx.say(m[2])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
hello, 1234
hello
12



=== TEST 4: not matched
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "foo")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched: nil



=== TEST 5: case sensitive by default
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "HELLO")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched: nil



=== TEST 6: case sensitive by default
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "HELLO", "i")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello



=== TEST 7: UTF-8 mode
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello章亦春", "HELLO.{2}", "iu")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello章亦



=== TEST 8: multi-line mode (^ at line head)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello\\nworld", "^world", "m")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
world



=== TEST 9: multi-line mode (. does not match \n)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello\\nworld", ".*", "m")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello



=== TEST 10: single-line mode (^ as normal)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello\\nworld", "^world", "s")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched: nil



=== TEST 11: single-line mode (dot all)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello\\nworld", ".*", "s")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello
world



=== TEST 12: extended mode (ignore whitespaces)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello\\nworld", "\\\\w     \\\\w", "x")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
he



=== TEST 13: bad pattern
--- config
    location /re {
        content_by_lua '
            rc, m = pcall(ngx.re.match, "hello\\nworld", "(abc")
            if rc then
                if m then
                    ngx.say(m[0])
                else
                    ngx.say("not matched: ", m)
                end
            else
                ngx.say("error: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: bad argument #2 to '?' (failed to compile regex "(abc": pcre_compile() failed: missing ) in "(abc")



=== TEST 14: bad option
--- config
    location /re {
        content_by_lua '
            rc, m = pcall(ngx.re.match, "hello\\nworld", ".*", "H")
            if rc then
                if m then
                    ngx.say(m[0])
                else
                    ngx.say("not matched: ", m)
                end
            else
                ngx.say("error: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: bad argument #3 to '?' (unknown flag "H")



=== TEST 15: extended mode (ignore whitespaces)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, world", "(world)|(hello)", "x")
            if m then
                ngx.say(m[0])
                ngx.say(m[1])
                ngx.say(m[2])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello
nil
hello

