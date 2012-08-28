# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    if (!defined $ENV{LD_PRELOAD}) {
        $ENV{LD_PRELOAD} = '';
    }

    if ($ENV{LD_PRELOAD} !~ /\bmockeagain\.so\b/) {
        $ENV{LD_PRELOAD} = "mockeagain.so $ENV{LD_PRELOAD}";
    }

    $ENV{MOCKEAGAIN} = 'w';

    $ENV{TEST_NGINX_EVENT_TYPE} = 'poll';
    $ENV{MOCKEAGAIN_WRITE_TIMEOUT_PATTERN} = 'hello, world';
    $ENV{TEST_NGINX_POSTPONE_OUTPUT} = 1;
}

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 1 + 1);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: flush wait - timeout
--- config
    send_timeout 100ms;
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- ignore_response
--- error_log eval
[qr/client timed out \(\d+: .*?timed out\)/]



=== TEST 2: send timeout timer got removed in time
--- config
    send_timeout 1234ms;
    location /test {
        content_by_lua '
            ngx.say(string.rep("blah blah blah", 10))
            -- ngx.flush(true)
            ngx.eof()
            for i = 1, 20 do
                ngx.sleep(0.1)
            end
        ';
    }
--- request
GET /test
--- stap
global evtime

F(ngx_http_handler) {
    delete evtime
}

M(timer-add) {
    if ($arg2 == 1234) {
        printf("add timer %d\n", $arg2)
        evtime[$arg1] = $arg2
    }
}

M(timer-del) {
    time = evtime[$arg1]
    if (time == 1234) {
        printf("del timer %d\n", time)
    }
}

M(timer-expire) {
    time = evtime[$arg1]
    if (time == 1234) {
        printf("expire timer %d\n", time)
        #print_ubacktrace()
    }
}
/*
probe syscall.writev.return {
    if (pid() == target()) {
        printf("writev: %s\n", retstr)
    }
}
*/
--- stap_out
add timer 1234
del timer 1234
--- ignore_response
--- no_error_log
[error]
--- timeout: 3

