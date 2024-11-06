# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua 'no_plan';

#worker_connections(1014);
master_on();
workers(2);
#log_level('warn');

repeat_each(2);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: use udp send buffer
--- config
    location /lua {
        content_by_lua_block {
            local udpsock = ngx.socket.udp()
            udpsock:settimeout(500)
            local host,port = "127.0.0.1",8080
            local ok, err = udpsock:setpeername(host, port)
            if not ok then
                ngx.say("============failed to connect to udp server: ", host, ",err:", err)
                return
            end
            local header_binary = "11"
            local serial_binary = "22"
            local log_msg_content = "3333333312345678901234567890123456789012345678901234567890"
            local msgStartIndex = 10
            local msgEndIndex = 20
            ok, err = udpsock:sendbuf(header_binary, serial_binary, log_msg_content, msgStartIndex, msgEndIndex)
            if not ok then
                ngx.say("============failed to send: ", host, ",err:", err)
                return
            end
            ngx.say("OK")
            
        }
    }
--- request
GET /lua
--- response_body_like
OK
--- no_error_log
[error]
