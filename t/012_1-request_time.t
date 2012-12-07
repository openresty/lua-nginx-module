# -*- mode: conf -*-
# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: start time
--- config
    location = /start {
        content_by_lua 'ngx.say(ngx.req.start_time())';
    }
--- request
GET /start
--- response_body_like: ^\d{10,}(\.\d{1,3})?$



=== TEST 2: start time in set_by_lua
--- config
    location = /start {
        set_by_lua $a 'return ngx.req.start_time()';
        echo $a;
    }
--- request
GET /start
--- response_body_like: ^\d{10,}(\.\d{1,3})?$


=== TEST 3: request time
--- config
    location = /req_time {
        content_by_lua '
            ngx.sleep(0.1)

            local req_time = ngx.now() - ngx.req.start_time()

            ngx.say(req_time)
            ngx.say(ngx.req.start_time() < ngx.now())
        ';
    }
--- request
GET /req_time
--- response_body_like chomp
^0\.1\d{10,}
true$


=== TEST 4: request time update
--- config
    location = /req_time {
            content_by_lua '
               ngx.sleep(0.1)

               local req_time = ngx.now() - ngx.req.start_time()

               ngx.sleep(0.1)

               ngx.update_time()

               local req_time_updated = ngx.now() - ngx.req.start_time()

               ngx.say(req_time)
               ngx.say(req_time_updated)
               ngx.say(req_time_updated > req_time)
            ';
    }
--- request
GET /req_time
--- response_body_like chomp
^0\.1\d{10,}
0\.\d{10,}
true$