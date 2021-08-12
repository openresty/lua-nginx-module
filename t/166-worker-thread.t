# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2 - 1);

our $HtmlDir = html_dir;

our $HttpConfig = qq{
    lua_package_path "$::HtmlDir/?.lua;./?.lua;;";
    lua_worker_thread_vm_pool_size 1;
};

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: hello from worker thread
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : hello



=== TEST 2: thread_pool not found
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
false : thread_pool not found



=== TEST 3: pass table
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, ok_or_err = ngx.run_worker_thread("testpool", "hello", "hello", {["hello"]="world", [1]={["embed"]=1}})
        ngx.say(ok, " , ", ok_or_err)
    }
}
--- user_files
>>> hello.lua
local function hello(arg1)
    if arg1.hello == "world" and arg1[1].embed == 1 then
        return true
    end
    return false
end
return {hello=hello}
--- request
GET /hello
--- response_body
true , true



=== TEST 4: expecting at least 3 arguments
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, err = ngx.run_worker_thread("testpool")
        ngx.say(ok, " : ", err)
    }
}
--- request
GET /hello
--- response_body
false : expecting at least 3 arguments



=== TEST 5: base64
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, base64 = ngx.run_worker_thread("testpool", "hello", "enc", "hello")
        ngx.say(ok, " , ", base64 == "aGVsbG8=")
    }
}
--- user_files
>>> hello.lua
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function enc(data)
    return ((data:gsub('.', function(x)
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

return {enc=enc}
--- request
GET /hello
--- response_body
true , true



=== TEST 6: return table
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, ret = ngx.run_worker_thread("testpool", "hello", "hello")
        if ret.hello == "world" and ret[1].embed == 1 then
            ngx.say(ok, " , ", true)
        end
    }
}
--- user_files
>>> hello.lua
local function hello()
    return {["hello"]="world", [1]={["embed"]=1}}
end
return {hello=hello}
--- request
GET /hello
--- response_body
true , true



=== TEST 7: unsupported argument type
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local function dummy() end
        local ok, err = ngx.run_worker_thread("testpool", "hello", "hello", dummy)
        ngx.say(ok, " : ", err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- error_code: 500



=== TEST 8: multiple return values
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, res1, res2 = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", res1, " , ", res2)
    }
}
--- user_files
>>> hello.lua
local function hello()
    return "hello", 200
end
return {hello=hello}
--- request
GET /hello
--- response_body
true : hello , 200



=== TEST 9: access ngx.* api
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", err)
    }
}
--- user_files
>>> hello.lua
local function hello()
    ngx.sleep(1)
    return "ok"
end
return {hello=hello}
--- request
GET /hello
--- response_body_like
false : .*attempt to index global 'ngx' \(a nil value\)



=== TEST 10: module not found
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", err)
    }
}
--- request
GET /hello
--- response_body_like
false : module 'hello' not found.*



=== TEST 11: the number of Lua VM exceeds the pool size
--- main_config
    thread_pool testpool threads=100;
--- http_config eval: $::HttpConfig
--- config
location /foo {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}

location /bar {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, foobar_or_err = ngx.run_worker_thread("testpool", "foobar", "foobar")
        ngx.say(ok, " : ", foobar_or_err)
    }
}

location /t {
    set $port $TEST_NGINX_SERVER_PORT;

    content_by_lua_block {
        local function t(path)
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET " .. path .. " HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            local ret, err, part = sock:receive("*a")
            local _, idx = string.find(ret, "\r\n\r\n");
            idx = idx + 1
            ngx.print(string.sub(ret, idx))
            ok, err = sock:close()
        end

        local t1 = ngx.thread.spawn(t, "/foo")
        local t2 = ngx.thread.spawn(t, "/bar")
        ngx.thread.wait(t1)
        ngx.thread.wait(t2)
    }
}
--- user_files
>>> hello.lua
local function hello()
    os.execute("sleep 3")
    return "hello"
end
return {hello=hello}
>>> foobar.lua
local function foobar()
    return "foobar"
end
return {foobar=foobar}
--- request
GET /t
--- response_body eval
"false : no available Lua vm\ntrue : hello\n"
--- timeout: 10



=== TEST 12: kill uthread before worker thread callback
--- main_config
    thread_pool testpool threads=100;
--- http_config eval: $::HttpConfig
--- config
location /foo {
    default_type 'text/plain';

    content_by_lua_block {
        local function t()
            local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
            ngx.say(ok, " : ", hello_or_err)
        end
        local t1 = ngx.thread.spawn(t)
        if ngx.var.arg_kill == "kill" then
            ngx.thread.kill(t1)
            ngx.say("killed")
        end
    }
}

location /t {
    set $port $TEST_NGINX_SERVER_PORT;

    content_by_lua_block {
        local function t(path)
            local sock = ngx.socket.tcp()
            local port = ngx.var.port
            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local req = "GET " .. path .. " HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n"

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            local ret, err, part = sock:receive("*a")
            local _, idx = string.find(ret, "\r\n\r\n");
            idx = idx + 1
            ngx.print(string.sub(ret, idx))
            ok, err = sock:close()
        end

        local t1 = ngx.thread.spawn(t, "/foo?kill=kill")
        ngx.thread.wait(t1)
        ngx.sleep(4)
        local t2 = ngx.thread.spawn(t, "/foo")
        ngx.thread.wait(t2)
    }
}
--- user_files
>>> hello.lua
local function hello()
    os.execute("sleep 3")
    return "hello"
end
return {hello=hello}
>>> foobar.lua
local function foobar()
    return "foobar"
end
return {foobar=foobar}
--- request
GET /t
--- response_body eval
"killed\ntrue : hello\n"
--- timeout: 20



=== TEST 13: exit before worker thread callback
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local function t()
            local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello", "hello")
            ngx.say(ok, " : ", hello_or_err)
        end
        ngx.thread.spawn(t)
        ngx.exit(200)
    }
}
--- user_files
>>> hello.lua
local function hello()
    os.execute("sleep 3")
    return "hello"
end
return {hello=hello}
--- request
GET /hello
--- response_body
--- timeout: 20
