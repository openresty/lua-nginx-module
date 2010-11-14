# vim:set ft=perl ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
log_level('debug'); # to ensure any log-level can be outputed

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: test log-level STDERR
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.STDERR, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log



=== TEST 2: test log-level EMERG
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.EMERG, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log



=== TEST 3: test log-level ALERT
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.ALERT, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log



=== TEST 4: test log-level CRIT
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.CRIT, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log



=== TEST 5: test log-level ERR
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.ERR, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log



=== TEST 6: test log-level WARN
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.WARN, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log



=== TEST 7: test log-level NOTICE
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.NOTICE, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log



=== TEST 8: test log-level INFO
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.INFO, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log



=== TEST 9: test log-level DEBUG
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.DEBUG, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log



=== TEST 10: regression test print()
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            print("hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log



=== TEST 11: print(nil)
--- config
    location /log {
        content_by_lua '
            print()
            print(nil)
            print("nil: ", nil)
            ngx.say("hi");
        ';
    }
--- request
GET /log
--- response_body
hi

