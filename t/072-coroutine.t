# vim:set ft=perl ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * blocks() * 2;

run_tests();

__DATA__

=== TEST 1: basic coroutine print
--- config
    location /lua {
        content_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

            function f()
                local cnt = 0
                while true do
                    ngx.say("Hello, ", cnt)
                    cy()
                    cnt = cnt + 1
                end
            end

            local c = cc(f)
            for i=1,3 do
                cr(c)
                ngx.say("***")
            end
        ';
    }
--- request
GET /lua
--- response_body
Hello, 0
***
Hello, 1
***
Hello, 2
***



=== TEST 2: basic coroutine2
--- config
    location /lua {
        content_by_lua '
            function f(fid)
                local cnt = 0
                while true do
                    ngx.say("cc", fid, ": ", cnt)
                    coroutine.yield()
                    cnt = cnt + 1
                end
            end

            local ccs = {}
            for i=1,3 do
                ccs[#ccs+1] = coroutine.create(function() f(i) end)
            end

            for i=1,6 do
                local cc = table.remove(ccs, 1)
                coroutine.resume(cc)
                ccs[#ccs+1] = cc
            end
        ';
    }
--- request
GET /lua
--- response_body
cc1: 0
cc2: 0
cc3: 0
cc1: 1
cc2: 1
cc3: 1
cc1: 2
cc2: 2
cc3: 2



=== TEST 3: basic coroutine and cosocket
--- config
    location /lua {
        content_by_lua '
            function worker(url)
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect(url, 80)
                coroutine.yield()
                if not ok then
                    ngx.say("failed to connect to: ", url, " error: ", err)
                    return
                end
                coroutine.yield()
                ngx.say("successfully connected to: ", url)
                sock:close()
            end

            local urls = {
                "www.taobao.com",
                "www.baidu.com",
                "www.google.com"
            }

            local ccs = {}
            for i, url in ipairs(urls) do
                local cc = coroutine.create(function() worker(url) end)
                ccs[#ccs+1] = cc
            end

            while true do
                local cc = table.remove(ccs, 1)
                local ok = coroutine.resume(cc)
                if ok then
                    ccs[#ccs+1] = cc
                end
            end

            ngx.say("*** All Done ***")
        ';
    }
--- request
GET /lua
--- response_body
successfully connected to: www.taobao.com
successfully connected to: www.baidu.com
successfully connected to: www.google.com
*** All Done ***
--- SKIP

