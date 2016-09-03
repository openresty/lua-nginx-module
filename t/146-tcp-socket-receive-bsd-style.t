# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua 'no_plan';

repeat_each(10);

log_level 'debug';

run_tests();

__DATA__

=== TEST 1: *b pattern for receive
--- config
    server_tokens off;
    location = /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:settimeout(100)
            assert(sock:connect("127.0.0.1", ngx.var.port))
            local req = {
                'GET /foo ',
                'HTTP/1.0\r\n',
                'Host: ',
                'localhost\r\n',
                'Connection: close\r\n\r\n',
            }
            for _, msg in ipairs(req) do
                sock:send(msg)
                ngx.sleep(0.01)
            end

            local i = 1
            local resp = {}
            local err
            while true do
                resp[i], err = sock:receive('*b')
                if err ~= nil then
                    ngx.log(ngx.ERR, "receive *b error: ", err)
                    break
                end

                local resp_str = table.concat(resp)
                if string.sub(resp_str, -15) == 'AAAAABBBBBCCCCC' then
                    ngx.say('ok')
                    break
                end
                if string.sub(resp_str, -12) == 'wwwxxxyyyzzz' then
                    ngx.say('ok')
                    break
                end
                i = i + 1
            end
            sock:close()
        }
    }

    location = /foo {
        content_by_lua_block {
            local resps = {
                {
                    "AAAAA",
                    "BBBBB",
                    "CCCCC",
                },
                {
                    "www",
                    "xxx",
                    "yyy",
                    "zzz",
                },
            }
            local i = math.random(2)
            local resp = resps[i]
            local length = 0
            for _, s in ipairs(resp) do
                length = length + #s
            end

            ngx.header['Content-Length'] = length
            ngx.flush(true)
            ngx.sleep(0.01)

            for _, s in ipairs(resp) do
                ngx.print(s)
                ngx.flush(true)
                ngx.sleep(0.01)
            end
        }
    }

--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
--- error_log
lua tcp socket read bsd

