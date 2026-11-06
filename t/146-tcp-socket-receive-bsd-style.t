# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua 'no_plan';

repeat_each(2);

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
            sock:settimeout(500)
            assert(sock:connect("127.0.0.1", ngx.var.port))
            local req = {
                'GET /foo HTTP/1.0\r\n',
                'Host: localhost\r\n',
                'Connection: close\r\n\r\n',
            }
            sock:send(req)

            -- skip http header
            while true do
                local data, err, _ = sock:receive('*l')
                if err then
                    ngx.say('unexpected error occurs when receiving http head: ' .. err)
                    return
                end
                if #data == 0 then -- read last line of head
                    break
                end
            end

            -- receive http body
            while true do
                local data, err = sock:receive('*b')
                if err then
                    if err ~= 'closed' then
                        ngx.say('unexpected err: ', err)
                    end
                    break
                end
                ngx.say(data)
            end

            sock:close()
        }
    }

    location = /foo {
        content_by_lua_block {
            local resp = {
                '1',
                '22',
                'hello world',
            }

            local length = 0
            for _, v in ipairs(resp) do
                length = length + #v
            end

            -- flush http header
            ngx.header['Content-Length'] = length
            ngx.flush(true)
            ngx.sleep(0.01)

            -- send http body
            for _, v in ipairs(resp) do
                ngx.print(v)
                ngx.flush(true)
                ngx.sleep(0.01)
            end
        }
    }

--- request
GET /t
--- response_body
1
22
hello world
--- no_error_log
[error]
--- error_log
lua tcp socket read bsd

