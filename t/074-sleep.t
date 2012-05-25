# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    $ENV{TEST_NGINX_POSTPONE_OUTPUT} = 1;
}

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => 11;

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sleep 0.5 - content
--- config
    location /test {
        content_by_lua '
            ngx.update_time();local before = ngx.now();
            ngx.sleep(0.5);
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.5 or delay > 0.51 then ngx.say("failed") 
            else ngx.say("ok") end
        ';
    }
--- request
GET /test
--- response_body
ok
--- error_log
lua ready to sleep
--- timeout: 1


=== TEST 2: sleep a - content
--- config
    location /test {
        content_by_lua '
            ngx.update_time();local before = ngx.now();
            ngx.sleep("a");
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.5 or delay > 0.51 then ngx.say("failed") 
            else ngx.say("ok") end
        ';
    }
--- request
GET /test
--- error_code: 500
--- error_log
bad argument #1 to 'sleep'


=== TEST 3: sleep 0.5 - rewrite
--- config
    location /test {
        rewrite_by_lua '
            ngx.update_time();local before = ngx.now();
            ngx.sleep(0.5);
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.5 or delay > 0.51 then ngx.say("failed") 
            else ngx.say("ok") end
        ';
        content_by_lua 'ngx.say("end")';
    }
--- request
GET /test
--- response_body
ok
end
--- error_log
lua ready to sleep
--- timeout: 1


=== TEST 4: sleep a - rewrite
--- config
    location /test {
        rewrite_by_lua '
            ngx.update_time();local before = ngx.now();
            ngx.sleep("a");
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.5 or delay > 0.51 then ngx.say("failed") 
            else ngx.say("ok") end
        ';
        content_by_lua 'ngx.say("end")';
    }
--- request
GET /test
--- error_code: 500
--- error_log
bad argument #1 to 'sleep'


=== TEST 5: sleep 0.5 - access
--- config
    location /test {
        access_by_lua '
            ngx.update_time();local before = ngx.now();
            ngx.sleep(0.5);
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.5 or delay > 0.51 then ngx.say("failed") 
            else ngx.say("ok") end
        ';
        content_by_lua 'ngx.say("end")';
    }
--- request
GET /test
--- response_body
ok
end
--- error_log
lua ready to sleep
--- timeout: 1


=== TEST 6: sleep a - access
--- config
    location /test {
        access_by_lua '
            ngx.update_time();local before = ngx.now();
            ngx.sleep("a");
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.5 or delay > 0.51 then ngx.say("failed") 
            else ngx.say("ok") end
        ';
        content_by_lua 'ngx.say("end")';
    }
--- request
GET /test
--- error_code: 500
--- error_log
bad argument #1 to 'sleep'


=== TEST 7: sleep 0.5 in subrequest - content
--- config
    location /test {
        content_by_lua '
            ngx.update_time();local before = ngx.now();
            ngx.location.capture("/sleep");
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.5 or delay > 0.51 then ngx.say("failed") 
            else ngx.say("ok") end
        ';
    }
    location /sleep {
        content_by_lua 'ngx.sleep(0.5)';
    }
--- request
GET /test
--- response_body
ok
--- error_log
lua ready to sleep
--- timeout: 1


=== TEST 8: sleep 0.5 in subrequest - rewrite_by_lua
--- config
    location /test {
        content_by_lua '
            ngx.update_time();local before = ngx.now();
            ngx.location.capture("/sleep");
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.5 or delay > 0.51 then ngx.say("failed") 
            else ngx.say("ok") end
        ';
    }
    location /sleep {
        rewrite_by_lua 'ngx.sleep(0.5)';
    }
--- request
GET /test
--- response_body
ok
--- error_log
lua ready to sleep
--- timeout: 1


=== TEST 9: sleep a in subrequest with bad argument
--- config
    location /test {
        content_by_lua '
            ngx.update_time();local before = ngx.now();
            local res = ngx.location.capture("/sleep");
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.1 then ngx.say("ok") 
            else ngx.say("failed") end
        ';
    }
    location /sleep {
        content_by_lua 'ngx.sleep("a")';
    }
--- request
GET /test
--- error_code: 200
--- response_body
ok
--- error_log
bad argument #1 to 'sleep'


=== TEST 10: sleep 0.5 - multi-times in access
--- config
    location /test {
        access_by_lua '
            ngx.update_time();local before = ngx.now();
            local i = 5
            while i > 0 do ngx.sleep(0.1);i=i-1; end
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.5 or delay > 0.51 then ngx.say("failed") 
            else ngx.say("ok") end
        ';
        content_by_lua 'ngx.say("end")';
    }
--- request
GET /test
--- response_body
ok
end
--- error_log
lua ready to sleep
--- timeout: 1


=== TEST 11: sleep 0.5 - multi-times in content
--- config
    location /test {
        content_by_lua '
            ngx.update_time();local before = ngx.now();
            local i = 5
            while i > 0 do ngx.sleep(0.1);i=i-1; end
            local now = ngx.now();
            local delay = now - before;
            if delay < 0.5 or delay > 0.51 then ngx.say("failed") 
            else ngx.say("ok") end
        ';
    }
--- request
GET /test
--- response_body
ok
--- error_log
lua ready to sleep
--- timeout: 1
--- ONLY

