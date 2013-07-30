# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use t::TestNginxLua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (2* blocks());

#no_diff();
no_long_string();

run_tests();

__DATA__

=== TEST 1: getlifetime after sleep 2 seconds
--- config
    location /t {
        content_by_lua '
            tcpsock = ngx.socket.tcp()
            local ok, err
            local port = 1984
            local epsilon = 30
            local interval_time = 2

            ok, err = tcpsock:connect("127.0.0.1", port)
            if not ok then
               ngx.say("failed to connect: ", err)
               return
            end

            ngx.sleep(interval_time)

            local lifetime, err = tcpsock:getlifetime()
            if not lifetime then
                ngx.say("failed to getlifetime: ", err)
                return
            end
            if math.abs(lifetime - interval_time*1000) <  epsilon then
               ngx.say("works")
            else
               ngx.say("error")
            end
            tcpsock:close()
        ';
    }
--- request
GET /t

--- response_body
works

=== TEST 2: get lifetime after setkeepalive
--- config
    location /t {
        content_by_lua '
            tcpsock = ngx.socket.tcp()
            local port = 1984
            local interval_time = 1
            local epsilon = 30

            local ok, err = tcpsock:connect("127.0.0.1", port)
            if not ok then
               ngx.say("failed to connect: ", err)
               return
            end

            ngx.sleep(interval_time)

            local lifetime, err = tcpsock:getlifetime()
            if not lifetime then
                ngx.say("failed to getlifetime: ", err)
                return
            end

            local ok, err = tcpsock:setkeepalive(0,1024)
            if not ok then
               ngx.say(err)
            end

            local ok, err = tcpsock:connect("127.0.0.1", port)
            if not ok then
               ngx.say("failed to connect: ", err)
               return
            end

            if math.abs(lifetime - interval_time*1000) <  epsilon then
               ngx.say("works")
            else
               ngx.say("error")
               ngx.say(lifetime)
               ngx.say(interval_time)
            end
            tcpsock:close()
        ';
    }
--- request
GET /t

--- response_body
works

=== TEST 3: sleep again after wake up from pool
--- config
    location /t {
        content_by_lua '
            tcpsock = ngx.socket.tcp()
            local port = 1984
            local epsilon = 30
            local interval_time = 1
            local ok, err = tcpsock:connect("127.0.0.1", port)
            if not ok then
               ngx.say("failed to connect: ", err)
               return
            end

            ngx.sleep(interval_time)

            local lifetime, err = tcpsock:getlifetime()
            if not lifetime then
                ngx.say("failed to getlifetime: ", err)
                return
            end
            local ok, err = tcpsock:setkeepalive(0,1024)
            if not ok then
               ngx.say(err)
            end
            local ok, err = tcpsock:connect("127.0.0.1", port)
            if not ok then
               ngx.say("failed to connect: ", err)
               return
            end

            --sleep again
            ngx.sleep(interval_time)

            local lifetime, err = tcpsock:getlifetime()
            if not lifetime then
                ngx.say("failed to getlifetime: ", err)
                return
            end
            if math.abs(lifetime - interval_time*2*1000) <  epsilon then
               ngx.say("works")
            else
               ngx.say("error")
            end
            tcpsock:close()
        ';
    }
--- request
GET /t

--- response_body
works
