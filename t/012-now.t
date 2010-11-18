# vim:set ft= ts=4 sw=4 et fdm=marker:
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

=== TEST 1: use ngx.now in content_by_lua
--- config
    location = /now {
        content_by_lua 'ngx.say(ngx.now())';
    }
--- request
GET /now
--- response_body_like: ^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$



=== TEST 2: use ngx.now in set_by_lua
--- config
    location = /now {
        set_by_lua $a 'return ngx.now()';
        echo $a;
    }
--- request
GET /now
--- response_body_like: ^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$



=== TEST 3: use ngx.utc_now in content_by_lua
--- config
    location = /utc_now {
        content_by_lua 'ngx.say(ngx.utc_now())';
    }
--- request
GET /utc_now
--- response_body_like: ^\d{10}$



=== TEST 4: use ngx.utc_now in set_by_lua
--- config
    location = /utc_now {
        set_by_lua $a 'return ngx.utc_now()';
        echo $a;
    }
--- request
GET /utc_now
--- response_body_like: ^\d{10}$

