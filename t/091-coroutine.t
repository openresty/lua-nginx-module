# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 5);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

our $StapScript = <<'_EOC_';
global ids, cur

function gen_id(k) {
    if (ids[k]) return ids[k]
    ids[k] = ++cur
    return cur
}

F(ngx_http_handler) {
    delete ids
    cur = 0
}

/*
F(ngx_http_lua_run_thread) {
    id = gen_id($ctx->cur_co)
    printf("run thread %d\n", id)
}

probe process("/usr/local/openresty-debug/luajit/lib/libluajit-5.1.so.2").function("lua_resume") {
    id = gen_id($L)
    printf("lua resume %d\n", id)
}
*/

M(http-lua-user-coroutine-resume) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("resume %x in %x\n", c, p)
}

M(http-lua-thread-yield) {
    println("thread yield")
}

/*
F(ngx_http_lua_coroutine_yield) {
    printf("yield %x\n", gen_id($L))
}
*/

M(http-lua-user-coroutine-yield) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("yield %x in %x\n", c, p)
}

F(ngx_http_lua_atpanic) {
    printf("lua atpanic(%d):", gen_id($L))
    print_ubacktrace();
}

M(http-lua-user-coroutine-create) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("create %x in %x\n", c, p)
}

F(ngx_http_lua_ngx_exec) { println("exec") }

F(ngx_http_lua_ngx_exit) { println("exit") }
F(ngx_http_lua_ffi_exit) { println("exit") }
_EOC_

no_shuffle();
no_long_string();
run_tests();

__DATA__

=== TEST 1: basic coroutine print
--- config
    location /lua {
        content_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

            local function f()
                local cnt = 0
                for i = 1, 20 do
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
--- stap2 eval: $::StapScript
--- response_body
Hello, 0
***
Hello, 1
***
Hello, 2
***
--- no_error_log
[error]



=== TEST 2: basic coroutine2
--- config
    location /lua {
        content_by_lua '
            local function f(fid)
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

            for i=1,9 do
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
--- no_error_log
[error]



=== TEST 3: basic coroutine and cosocket
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /lua {
        content_by_lua '
            local function worker(url)
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
                "agentzh.org",
                "openresty.org"
            }

            local ccs = {}
            for i, url in ipairs(urls) do
                local cc = coroutine.create(function() worker(url) end)
                ccs[#ccs+1] = cc
            end

            while true do
                if #ccs == 0 then break end
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
successfully connected to: agentzh.org
successfully connected to: openresty.org
*** All Done ***
--- no_error_log
[error]
--- timeout: 10



=== TEST 4: coroutine.wrap(generate prime numbers)
--- config
    location /lua {
        content_by_lua '
            -- generate all the numbers from 2 to n
            local function gen (n)
              return coroutine.wrap(function ()
                for i=2,n do coroutine.yield(i) end
              end)
            end

            -- filter the numbers generated by g, removing multiples of p
            local function filter (p, g)
              return coroutine.wrap(function ()
                while 1 do
                  local n = g()
                  if n == nil then return end
                  if math.fmod(n, p) ~= 0 then coroutine.yield(n) end
                end
              end)
            end

            local N = 10
            local x = gen(N)		-- generate primes up to N
            while 1 do
              local n = x()		-- pick a number until done
              if n == nil then break end
              ngx.say(n)		-- must be a prime number
              x = filter(n, x)	-- now remove its multiples
            end
        ';
    }
--- request
GET /lua
--- response_body
2
3
5
7
--- no_error_log
[error]



=== TEST 5: coroutine.wrap(generate prime numbers,reset create and resume)
--- config
    location /lua {
        content_by_lua '
            coroutine.create = nil
            coroutine.resume = nil
            -- generate all the numbers from 2 to n
            local function gen (n)
              return coroutine.wrap(function ()
                for i=2,n do coroutine.yield(i) end
              end)
            end

            -- filter the numbers generated by g, removing multiples of p
            local function filter (p, g)
              return coroutine.wrap(function ()
                while 1 do
                  local n = g()
                  if n == nil then return end
                  if math.fmod(n, p) ~= 0 then coroutine.yield(n) end
                end
              end)
            end

            local N = 10 
            local x = gen(N)		-- generate primes up to N
            while 1 do
              local n = x()		-- pick a number until done
              if n == nil then break end
              ngx.say(n)		-- must be a prime number
              x = filter(n, x)	-- now remove its multiples
            end
        ';
    }
--- request
GET /lua
--- response_body
2
3
5
7
--- no_error_log
[error]



=== TEST 6: coroutine.wrap(generate fib)
--- config
    location /lua {
        content_by_lua '
            local function generatefib (n)
              return coroutine.wrap(function ()
                local a,b = 1, 1
                while a <= n do
                  coroutine.yield(a)
                  a, b = b, a+b
                end
              end)
            end

            -- In lua, because OP_TFORLOOP uses luaD_call to execute the iterator function,
            -- and luaD_call is a C function, so we can not yield in the iterator function.
            -- So the following case(using for loop) will be failed.
            -- Luajit is OK.
            if package.loaded["jit"] then
                for i in generatefib(1000) do ngx.say(i) end
            else
                local gen = generatefib(1000)
                while true do
                    local i = gen()
                    if not i then break end
                    ngx.say(i)
                end
            end
        ';
    }
--- request
GET /lua
--- response_body
1
1
2
3
5
8
13
21
34
55
89
144
233
377
610
987
--- no_error_log
[error]



=== TEST 7: coroutine wrap and cosocket
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /lua {
        content_by_lua '
            local function worker(url)
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
                "agentzh.org",
                "openresty.org"
            }

            local cfs = {}
            for i, url in ipairs(urls) do
                local cf = coroutine.wrap(function() worker(url) end)
                cfs[#cfs+1] = cf
            end

            for i=1,#cfs do cfs[i]() end
            for i=1,#cfs do cfs[i]() end
            for i=1,#cfs do cfs[i]() end

            ngx.say("*** All Done ***")
        ';
    }
--- request
GET /lua
--- response_body
successfully connected to: agentzh.org
successfully connected to: openresty.org
*** All Done ***
--- no_error_log
[error]
--- timeout: 10



=== TEST 8: coroutine status, running
--- config
    location /lua {
        content_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield
            local st, rn = coroutine.status, coroutine.running

            local function f(self)
                local cnt = 0
                if rn() ~= self then ngx.say("error"); return end
                ngx.say("running: ", st(self)) --running
                cy()
                local c = cc(function(father)
                    ngx.say("normal: ", st(father))
                end) -- normal
                cr(c, self)
            end

            local c = cc(f)
            ngx.say("suspended: ", st(c)) -- suspended
            cr(c, c)
            ngx.say("suspended: ", st(c)) -- suspended
            cr(c, c)
            ngx.say("dead: ", st(c)) -- dead
        ';
    }
--- request
GET /lua
--- response_body
suspended: suspended
running: running
suspended: suspended
normal: normal
dead: dead
--- no_error_log
[error]



=== TEST 9: entry coroutine yielded will be resumed immediately
--- config
    location /lua {
        content_by_lua '
            ngx.say("[", {coroutine.yield()}, "]")
            ngx.say("[", {coroutine.yield(1, "a")}, "]")
            ngx.say("done")
        ';
    }
--- request
GET /lua
--- response_body
[]
[]
done
--- no_error_log
[error]



=== TEST 10: thread traceback (multi-thread)
--- config
    location /lua {
        content_by_lua '
            local f = function(cr) coroutine.resume(cr) end
            -- emit a error
            local g = function() unknown.unknown = 1 end
            local l1 = coroutine.create(f)
            local l2 = coroutine.create(g)
            coroutine.resume(l1, l2)
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- response_body
hello
--- error_log eval
["stack traceback:", "coroutine 0:", "coroutine 1:", "coroutine 2:"]



=== TEST 11: thread traceback (only the entry thread)
--- config
    location /lua {
        content_by_lua '
            -- emit a error
            unknown.unknown = 1
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- error_code: 500
--- error_log eval
["stack traceback:", "coroutine 0:"]



=== TEST 12: bug: resume dead coroutine with args
--- config
    location /lua {
        content_by_lua '
            local function print(...)
                local args = {...}
                local is_first = true
                for i,v in ipairs(args) do
                    if is_first then
                        is_first = false
                    else
                        ngx.print(" ")
                    end
                    ngx.print(v)
                end
                ngx.print("\\\n")
            end

            local function foo (a)
                print("foo", a)
                return coroutine.yield(2*a)
            end

            local co = coroutine.create(function (a,b)
                    print("co-body", a, b)
                    local r = foo(a+1)
                    print("co-body", r)
                    local r, s = coroutine.yield(a+b, a-b)
                    print("co-body", r, s)
                    return b, "end"
                end)

            print("main", coroutine.resume(co, 1, 10))
            print("main", coroutine.resume(co, "r"))
            print("main", coroutine.resume(co, "x", "y"))
            print("main", coroutine.resume(co, "x", "y"))
        ';
    }
--- request
GET /lua
--- response_body
co-body 1 10
foo 2
main true 4
co-body r
main true 11 -9
co-body x y
main true 10 end
main false cannot resume dead coroutine
--- no_error_log
[error]



=== TEST 13: deeply nested coroutines
--- config
    location /lua {
        content_by_lua '
            local create = coroutine.create
            local resume = coroutine.resume
            local yield = coroutine.yield
            local g
            local function f()
                ngx.say("f begin")
                yield()
                local c2 = create(g)
                ngx.say("1: resuming c2")
                resume(c2)
                ngx.say("2: resuming c2")
                resume(c2)
                yield()
                ngx.say("3: resuming c2")
                resume(c2)
                ngx.say("f done")
            end

            function g()
                ngx.say("g begin")
                yield()
                ngx.say("g going")
                yield()
                ngx.say("g done")
            end

            local c1 = create(f)
            ngx.say("1: resuming c1")
            resume(c1)
            ngx.say("2: resuming c1")
            resume(c1)
            ngx.say("3: resuming c1")
            resume(c1)
            ngx.say("main done")
        ';
    }
--- request
GET /lua
--- response_body
1: resuming c1
f begin
2: resuming c1
1: resuming c2
g begin
2: resuming c2
g going
3: resuming c1
3: resuming c2
g done
f done
main done
--- no_error_log
[error]



=== TEST 14: using ngx.exit in user coroutines
--- config
    location /lua {
        content_by_lua '
            local create = coroutine.create
            local resume = coroutine.resume
            local yield = coroutine.yield

            local code = 400
            local g

            local function f()
                local c2 = create(g)
                yield()
                code = code + 1
                resume(c2)
                yield()
                resume(c2)
            end

            function g()
                code = code + 1
                yield()
                code = code + 1
                ngx.exit(code)
            end

            local c1 = create(f)
            resume(c1)
            resume(c1)
            resume(c1)
            ngx.say("done")
        ';
    }
--- request
GET /lua
--- stap eval: $::StapScript
--- stap_out
create 2 in 1
resume 2 in 1
create 3 in 2
yield 2 in 1
resume 2 in 1
resume 3 in 2
yield 3 in 2
yield 2 in 1
resume 2 in 1
resume 3 in 2
exit

--- response_body_like: 403 Forbidden
--- error_code: 403
--- no_error_log
[error]



=== TEST 15: using ngx.exec in user coroutines
--- config
    location /lua {
        content_by_lua '
            local create = coroutine.create
            local resume = coroutine.resume
            local yield = coroutine.yield

            local code = 0
            local g

            local function f()
                local c2 = create(g)
                yield()
                code = code + 1
                resume(c2)
                yield()
                resume(c2)
            end

            function g()
                code = code + 1
                yield()
                code = code + 1
                ngx.exec("/n/" .. code)
            end

            local c1 = create(f)
            resume(c1)
            resume(c1)
            resume(c1)
            ngx.say("done")
        ';
    }

    location ~ '^/n/(\d+)' {
        echo "num: $1";
    }

--- stap eval: $::StapScript
--- stap_out
create 2 in 1
resume 2 in 1
create 3 in 2
yield 2 in 1
resume 2 in 1
resume 3 in 2
yield 3 in 2
yield 2 in 1
resume 2 in 1
resume 3 in 2
exec

--- request
GET /lua
--- response_body
num: 3
--- no_error_log
[error]



=== TEST 16: coroutine.create in header_filter_by_lua
--- config
    location /lua {
        echo hello;
        header_filter_by_lua '
            local function f()
                yield()
            end

            local c1 = coroutine.create(f)
            ngx.say("done")
        ';
    }
--- request
GET /lua
--- ignore_response
--- error_log
API disabled in the context of header_filter_by_lua*



=== TEST 17: resume coroutines from within another one that is not its parent
--- config
    location /t {
        content_by_lua '
            local print = ngx.say

            local c1, c2

            local function f()
                print("f 1")
                print(coroutine.resume(c2))
                print("f 2")
            end

            local function g()
                print("g 1")
                -- print(coroutine.resume(c1))
                print("g 2")
            end

            c1 = coroutine.create(f)
            c2 = coroutine.create(g)

            coroutine.resume(c1)
        ';
    }
--- request
GET /t
--- response_body
f 1
g 1
g 2
true
f 2
--- no_error_log
[error]



=== TEST 18: infinite recursive calls of coroutine.resume
--- config
    location /t {
        content_by_lua '
            local print = ngx.say

            local c1, c2

            local function f()
                print("f 1")
                print(coroutine.resume(c2))
                print("f 2")
            end

            local function g()
                print("g 1")
                print(coroutine.resume(c1))
                print("g 2")
            end

            c1 = coroutine.create(f)
            c2 = coroutine.create(g)

            coroutine.resume(c1)
        ';
    }
--- request
GET /t
--- stap2 eval: $::StapScript
--- response_body
f 1
g 1
falsecannot resume normal coroutine
g 2
true
f 2
--- no_error_log
[error]



=== TEST 19: resume running (entry) coroutines
--- config
    location /t {
        content_by_lua '
            ngx.say(coroutine.status(coroutine.running()))
            ngx.say(coroutine.resume(coroutine.running()))
        ';
    }
--- request
GET /t
--- response_body
running
falsecannot resume running coroutine
--- no_error_log
[error]



=== TEST 20: resume running (user) coroutines
--- config
    location /t {
        content_by_lua '
            local co
            local function f()
                ngx.say("f: ", coroutine.status(co))
                ngx.say("f: ", coroutine.resume(co))
            end
            co = coroutine.create(f)
            ngx.say("chunk: ", coroutine.status(co))
            ngx.say("chunk: ", coroutine.resume(co))
        ';
    }
--- request
GET /t
--- response_body
chunk: suspended
f: running
f: falsecannot resume running coroutine
chunk: true
--- no_error_log
[error]



=== TEST 21: user coroutine end with errors, and the parent coroutine gets the right status
--- config
    location /t {
        content_by_lua '
            local co
            local function f()
                error("bad")
            end
            co = coroutine.create(f)
            ngx.say("child: resume: ", coroutine.resume(co))
            ngx.say("child: status: ", coroutine.status(co))
            ngx.say("parent: status: ", coroutine.status(coroutine.running()))
        ';
    }
--- request
GET /t
--- response_body eval
qr/^child: resume: falsecontent_by_lua\(nginx\.conf:\d+\):4: bad
child: status: dead
parent: status: running
$/s
--- error_log eval
qr/lua coroutine: runtime error: content_by_lua\(nginx\.conf:\d+\):4: bad/



=== TEST 22: entry coroutine is yielded by hand and still gets the right status
--- config
    location /t {
        content_by_lua '
            local co = coroutine.running()
            ngx.say("status: ", coroutine.status(co))
            coroutine.yield(co)
            ngx.say("status: ", coroutine.status(co))
        ';
    }
--- request
GET /t
--- response_body
status: running
status: running
--- no_error_log
[error]



=== TEST 23: github issue #208: coroutine as iterator doesn't work
--- config
    location = /t {
        content_by_lua '
            local say = ngx.say
            local wrap, yield = coroutine.wrap, coroutine.yield

            local function it(it_state)
              for i = 1, it_state.i do
                yield(it_state.path, tostring(i))
              end
              return nil
            end

            local function it_factory(path)
              local it_state = { i = 10, path = path }
              return wrap(it), it_state
            end

            --[[
            for path, value in it_factory("test") do
              say(path, value)
            end
            ]]

            do
              local f, s, var = it_factory("test")
              while true do
                local path, value = f(s, var)
                var = path
                if var == nil then break end
                say(path, value)
              end
            end
        ';
    }
--- request
    GET /t
--- more_headers
Cookie: abc=32
--- stap2 eval: $::StapScript
--- response_body
test1
test2
test3
test4
test5
test6
test7
test8
test9
test10
--- no_error_log
[error]



=== TEST 24: init_by_lua + our own coroutines in content_by_lua
--- http_config
    init_by_lua 'return';
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /lua {
        content_by_lua '
            local function worker(url)
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
                "agentzh.org",
            }

            local ccs = {}
            for i, url in ipairs(urls) do
                local cc = coroutine.create(function() worker(url) end)
                ccs[#ccs+1] = cc
            end

            while true do
                if #ccs == 0 then break end
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
successfully connected to: agentzh.org
*** All Done ***
--- no_error_log
[error]
--- timeout: 10



=== TEST 25: init_by_lua_file + our own coroutines in content_by_lua
--- http_config
    init_by_lua_file html/init.lua;

--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /lua {
        content_by_lua '
            local function worker(url)
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
                "agentzh.org"
            }

            local ccs = {}
            for i, url in ipairs(urls) do
                local cc = coroutine.create(function() worker(url) end)
                ccs[#ccs+1] = cc
            end

            while true do
                if #ccs == 0 then break end
                local cc = table.remove(ccs, 1)
                local ok = coroutine.resume(cc)
                if ok then
                    ccs[#ccs+1] = cc
                end
            end

            ngx.say("*** All Done ***")
        ';
    }
--- user_files
>>> init.lua
return

--- request
GET /lua
--- response_body
successfully connected to: agentzh.org
*** All Done ***
--- no_error_log
[error]
--- timeout: 10



=== TEST 26: mixing coroutine.* API between init_by_lua and other contexts (github #304) - init_by_lua
--- http_config
    init_by_lua '
          co_wrap = coroutine.wrap
          co_yield = coroutine.yield
    ';

--- config
    location /cotest {
        content_by_lua '
            local function generator()
                return co_wrap(function()
                    co_yield("data")
                end)
            end

            local co = generator()
            local data = co()
            ngx.say(data)
        ';
    }

--- request
GET /cotest
--- stap2 eval: $::StapScript
--- response_body
data
--- no_error_log
[error]



=== TEST 27: mixing coroutine.* API between init_by_lua and other contexts (github #304) - init_by_lua_file
--- http_config
    init_by_lua_file html/init.lua;

--- config
    location /cotest {
        content_by_lua '
            local function generator()
                return co_wrap(function()
                    co_yield("data")
                end)
            end

            local co = generator()
            local data = co()
            ngx.say(data)
        ';
    }

--- user_files
>>> init.lua
co_wrap = coroutine.wrap
co_yield = coroutine.yield

--- request
GET /cotest
--- stap2 eval: $::StapScript
--- response_body
data
--- no_error_log
[error]



=== TEST 28: coroutine context collicisions
--- config
    location /lua {
        content_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

            local function f()
                return 3
            end

            for i = 1, 10 do
                collectgarbage()
                local c = cc(f)
                if coroutine.status(c) == "dead" then
                    ngx.say("found a dead coroutine")
                    return
                end
                cr(c)
            end
            ngx.say("ok")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- response_body
ok
--- no_error_log
[error]



=== TEST 29: require "coroutine"
--- config
    location /lua {
        content_by_lua '
            local coroutine = require "coroutine"
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

            local function f()
                local cnt = 0
                for i = 1, 20 do
                    ngx.say("Hello, ", cnt)
                    ngx.sleep(0.001)
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
--- stap2 eval: $::StapScript
--- response_body
Hello, 0
***
Hello, 1
***
Hello, 2
***
--- no_error_log
[error]



=== TEST 30: basic coroutine in header_filter_by_lua
--- config
    location = /t {
        echo ok;
        header_filter_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

            local function f()
                local cnt = 0
                for i = 1, 20 do
                    print("co yield: ", cnt)
                    cy()
                    cnt = cnt + 1
                end
            end

            local c = cc(f)
            for i = 1, 3 do
                print("co resume.")
                cr(c)
            end
        ';
    }
--- request
GET /t
--- response_body
ok
--- grep_error_log eval: qr/co (?:yield: \d+|resume\.)/
--- grep_error_log_out
co resume.
co yield: 0
co resume.
co yield: 1
co resume.
co yield: 2
--- no_error_log
[error]



=== TEST 31: basic coroutine in body_filter_by_lua
--- config
    location = /t {
        echo ok;
        body_filter_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

            local function f()
                local cnt = 0
                for i = 1, 20 do
                    print("co yield: ", cnt)
                    cy()
                    cnt = cnt + 1
                end
            end

            local c = cc(f)
            for i = 1, 3 do
                print("co resume.")
                cr(c)
            end
        ';
    }
--- request
GET /t
--- response_body
ok
--- grep_error_log eval: qr/co (?:yield: \d+|resume\.)/
--- grep_error_log_out
co resume.
co yield: 0
co resume.
co yield: 1
co resume.
co yield: 2
co resume.
co yield: 0
co resume.
co yield: 1
co resume.
co yield: 2

--- no_error_log
[error]
