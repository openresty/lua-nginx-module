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
            local interval_time = 1

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
            ngx.say(lifetime)
            tcpsock:close()
        ';
    }
--- request
GET /t

--- response_body_like chomp
^9[5-9]\d$|^10[0-4]\d$

=== TEST 2: get lifetime after setkeepalive
--- config
    location /t {
        content_by_lua '
            tcpsock = ngx.socket.tcp()
            local port = 1984
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

            ngx.say(lifetime)
            tcpsock:close()
        ';
    }
--- request
GET /t

--- response_body_like chomp
^9[5-9]\d$|^10[0-4]\d$

=== TEST 3: sleep again after wake up from pool
--- config
    location /t {
        content_by_lua '
            tcpsock = ngx.socket.tcp()
            local port = 1984
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
            ngx.say(lifetime)
            tcpsock:close()
        ';
    }
--- request
GET /t

--- response_body_like chomp
^19[5-9]\d$|^20[0-4]\d$
