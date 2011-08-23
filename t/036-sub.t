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

=== TEST 1: matched but w/o variables
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[a-z]+", "howdy")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
howdy, world
1



=== TEST 2: not matched
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[A-Z]+", "howdy")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, world
0



=== TEST 3: matched and with variables
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("a b c d", "(b) (c)", "[$0] [$1] [$2] [$3] [$134]")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
a [b c] [b] [c] [] [] d
1



=== TEST 4: matched and with named variables
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "a b c d",
                "(b) (c)", "[$0] [$1] [$2] [$3] [$hello]")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [$2] [$3] [$hello]"
nil



=== TEST 5: matched and with named variables (bracketed)
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "a b c d",
                "(b) (c)", "[$0] [$1] [$2] [$3] [${hello}]")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [$2] [$3] [${hello}]"
nil



=== TEST 6: matched and with bracketed variables
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134}]")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
[b c] [b] [c] [] [] d
1



=== TEST 7: matched and with bracketed variables (unmatched brackets)
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134]")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [${2}] [$3] [${134]"
nil



=== TEST 8: matched and with bracketed variables (unmatched brackets)
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [${2}] [$3] [${134"
nil



=== TEST 9: matched and with bracketed variables (unmatched brackets)
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [${2}] [$3] [${"
nil



=== TEST 10: trailing $
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [$")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [${2}] [$3] [$"
nil



=== TEST 11: matched but w/o variables and with literal $
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[a-z]+", "ho$$wdy")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
ho$wdy, world
1



=== TEST 12: non-anchored match
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234", "[0-9]", "x")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, x234
1



=== TEST 13: anchored match
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234", "[0-9]", "x", "a")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, 1234
0

