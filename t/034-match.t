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



=== TEST 2: escaping sequences
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "(\\\\d+)")
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



=== TEST 3: escaping sequences (bad)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "(\\d+)")
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
not matched!



=== TEST 4: escaping sequences in [[ ... ]]
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "[[\\d+]]")
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
not matched!



=== TEST 5: single capture
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



=== TEST 6: multiple captures
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



=== TEST 7: not matched
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



=== TEST 8: case sensitive by default
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



=== TEST 9: case sensitive by default
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



=== TEST 10: UTF-8 mode
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



=== TEST 11: multi-line mode (^ at line head)
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



=== TEST 12: multi-line mode (. does not match \n)
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



=== TEST 13: single-line mode (^ as normal)
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



=== TEST 14: single-line mode (dot all)
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



=== TEST 15: extended mode (ignore whitespaces)
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



=== TEST 16: bad pattern
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



=== TEST 17: bad option
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



=== TEST 18: extended mode (ignore whitespaces)
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



=== TEST 19: optional trailing captures
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+)(h?)")
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
--- response_body eval
"1234
1234

"



=== TEST 20: anchored match (failed)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+)", "a")
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
not matched!



=== TEST 21: anchored match (succeeded)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("1234, hello", "([0-9]+)", "a")
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



=== TEST 22: match with ctx but no pos
--- config
    location /re {
        content_by_lua '
            local ctx = {}
            m = ngx.re.match("1234, hello", "([0-9]+)", "", ctx)
            if m then
                ngx.say(m[0])
                ngx.say(ctx.pos)
            else
                ngx.say("not matched!")
                ngx.say(ctx.pos)
            end
        ';
    }
--- request
    GET /re
--- response_body
1234
4



=== TEST 23: match with ctx and a pos
--- config
    location /re {
        content_by_lua '
            local ctx = { pos = 2 }
            m = ngx.re.match("1234, hello", "([0-9]+)", "", ctx)
            if m then
                ngx.say(m[0])
                ngx.say(ctx.pos)
            else
                ngx.say("not matched!")
                ngx.say(ctx.pos)
            end
        ';
    }
--- request
    GET /re
--- response_body
34
4

