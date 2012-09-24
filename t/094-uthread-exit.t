# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= '11211';

#no_shuffle();
no_long_string();
run_tests();

__DATA__

=== TEST 5: exit in user thread (entry thread is still pending to run)
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.say("hello in thread")
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.create(f)
            ngx.say("after")
            ngx.sleep(1)
            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

M(timer-add) {
    if ($arg2 == 1000) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 1000) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 1000) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}
_EOC_

--- stap_out
create 2 in 1
create user thread 2 in 1
delete thread 2
delete thread 1

--- response_body
before
hello in thread
--- no_error_log
[error]



=== TEST 6: exit in user thread (entry thread is still pending on ngx.sleep)
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.create(f)
            ngx.say("after")
            ngx.sleep(1)
            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 1000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 1000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
    /*
    if (tm == 1000) {
        print_ubacktrace()
    }
    */
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 1000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_sleep_cleanup) {
    println("lua sleep cleanup")
}
_EOC_

--- stap_out
create 2 in 1
create user thread 2 in 1
add timer 100
add timer 1000
expire timer 100
lua sleep cleanup
delete timer 1000
delete thread 2
delete thread 1
free request

--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 7: exit in a user thread (another user thread is still pending on ngx.sleep)
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.sleep(0.1)
                ngx.say("f")
                ngx.exit(0)
            end

            function g()
                ngx.sleep(1)
                ngx.say("g")
            end

            ngx.thread.create(f)
            ngx.thread.create(g)
            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 1000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 1000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
    /*
    if (tm == 1000) {
        print_ubacktrace()
    }
    */
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 1000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_sleep_cleanup) {
    println("lua sleep cleanup")
}
_EOC_

--- stap_out
create 2 in 1
create user thread 2 in 1
add timer 100
create 3 in 1
create user thread 3 in 1
add timer 1000
delete thread 1
expire timer 100
lua sleep cleanup
delete timer 1000
delete thread 2
delete thread 3
free request

--- response_body
end
f
--- no_error_log
[error]



=== TEST 8: exit in user thread (entry already quits)
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.sleep(0.1)
                ngx.say("exiting the user thread")
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.create(f)
            ngx.say("after")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create user thread 2 in 1
delete thread 1
delete thread 2

--- response_body
before
after
exiting the user thread
--- no_error_log
[error]

