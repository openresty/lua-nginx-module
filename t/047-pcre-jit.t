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
no_long_string();
run_tests();

__DATA__

=== TEST 1: matched with j
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+)", "j")
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



=== TEST 2: not matched with j
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, world", "([0-9]+)", "j")
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



=== TEST 3: matched with jo
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+)", "jo")
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



=== TEST 4: not matched with jo
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, world", "([0-9]+)", "jo")
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



=== TEST 5: matched with d
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello", "(he|hell)", "d")
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
hell



=== TEST 6: not matched with j
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("world", "(he|hell)", "d")
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



=== TEST 7: matched with do
--- ONLY
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello", "he|hell", "do")
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
hell
nil
nil



=== TEST 8: not matched with do
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("world", "([0-9]+)", "do")
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

