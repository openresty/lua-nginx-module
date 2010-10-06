# vim:set ft=perl ts=4 sw=4 et fdm=marker:
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

=== TEST 1: use ngx.get_now in content_by_lua
--- config
    location = /now {
        content_by_lua 'ngx.say(ngx.get_now())';
    }
--- request
GET /now
--- response_body_like: ^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$



=== TEST 2: use ngx.get_now in set_by_lua
--- config
    location = /now {
        set_by_lua $a 'return ngx.get_now()';
        echo $a;
    }
--- request
GET /now
--- response_body_like: ^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$



=== TEST 3: use ngx.get_now_ts in content_by_lua
--- config
    location = /now_ts {
        content_by_lua 'ngx.say(ngx.get_now_ts())';
    }
--- request
GET /now_ts
--- response_body_like: ^\d{10}$



=== TEST 4: use ngx.get_now_ts in set_by_lua
--- config
    location = /now_ts {
        set_by_lua $a 'return ngx.get_now_ts()';
        echo $a;
    }
--- request
GET /now_ts
--- response_body_like: ^\d{10}$

