# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: gmatch
--- config
    location /re {
        content_by_lua '
            for m in ngx.re.gmatch("hello, world", "[a-z]+") do
                if m then
                    ngx.say(m[0])
                else
                    ngx.say("not matched: ", m)
                end
            end
        ';
    }
--- request
    GET /re
--- response_body
hello
world



=== TEST 2: fail to match
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[0-9]")
            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end
        ';
    }
--- request
    GET /re
--- response_body
nil
nil
nil



=== TEST 3: match but iterate more times (not just match at the end)
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world!", "[a-z]+")
            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end
        ';
    }
--- request
    GET /re
--- response_body
hello
world
nil
nil



=== TEST 4: match but iterate more times (just matched at the end)
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[a-z]+")
            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end
        ';
    }
--- request
    GET /re
--- response_body
hello
world
nil
nil



=== TEST 5: anchored match (failed)
--- config
    location /re {
        content_by_lua '
            it = ngx.re.gmatch("hello, 1234", "([0-9]+)", "a")
            ngx.say(it())
        ';
    }
--- request
    GET /re
--- response_body
nil



=== TEST 6: anchored match (succeeded)
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("12 hello 34", "[0-9]", "a")
            local m = it()
            ngx.say(m[0])
            m = it()
            ngx.say(m[0])
            ngx.say(it())
        ';
    }
--- request
    GET /re
--- response_body
1
2
nil



=== TEST 7: non-anchored gmatch
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("12 hello 34", "[0-9]")
            local m = it()
            ngx.say(m[0])
            m = it()
            ngx.say(m[0])
            m = it()
            ngx.say(m[0])
            m = it()
            ngx.say(m[0])
            m = it()
            ngx.say(m)
        ';
    }
--- request
    GET /re
--- response_body
1
2
3
4
nil



=== TEST 8: anchored match (succeeded)
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("12 hello 34", "[0-9]", "a")
            local m = it()
            ngx.say(m[0])
            m = it()
            ngx.say(m[0])
            ngx.say(it())
        ';
    }
--- request
    GET /re
--- response_body
1
2
nil



=== TEST 9: anchored match (succeeded, set_by_lua)
--- config
    location /re {
        set_by_lua $res '
            local it = ngx.re.gmatch("12 hello 34", "[0-9]", "a")
            local m = it()
            return m[0]
        ';
        echo $res;
    }
--- request
    GET /re
--- response_body
1

