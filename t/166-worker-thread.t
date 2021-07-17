# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

our $HtmlDir = html_dir;

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
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
return function()
    return "hello"
end
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
        local ok, hello_or_err = ngx.run_worker_thread("testpool", "hello")
        ngx.say(ok, " : ", hello_or_err)
    }
}
--- user_files
>>> hello.lua
return function()
    return "hello"
end
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
        local ok, ok_or_err = ngx.run_worker_thread("testpool", "hello", {["hello"]="world", [1]={["embed"]=1}})
        ngx.say(ok, " , ", ok_or_err)
    }
}
--- user_files
>>> hello.lua
return function(arg1)
    if arg1.hello == "world" and arg1[1].embed == 1 then
        return true
    end
    return false
end
--- request
GET /hello
--- response_body
true , true



=== TEST 4: expecting at least 2 arguments
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
false : expecting at least 2 arguments



=== TEST 5: base64
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, base64 = ngx.run_worker_thread("testpool", "hello", "hello")
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

return function(arg1)
    return enc(arg1)
end
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
        local ok, ret = ngx.run_worker_thread("testpool", "hello")
        if ret.hello == "world" and ret[1].embed == 1 then
            ngx.say(ok, " , ", true)
        end
    }
}
--- user_files
>>> hello.lua
return function()
    return {["hello"]="world", [1]={["embed"]=1}}
end
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
        local ok, err = ngx.run_worker_thread("testpool", "hello", dummy)
        ngx.say(ok, " : ", err)
    }
}
--- user_files
>>> hello.lua
return function()
    return "hello"
end
--- request
GET /hello
--- response_body
false : unsupported argument type



=== TEST 8: multiple return values
--- main_config
    thread_pool testpool threads=100;
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
location /hello {
    default_type 'text/plain';

    content_by_lua_block {
        local ok, res1, res2 = ngx.run_worker_thread("testpool", "hello")
        ngx.say(ok, " : ", res1, " , ", res2)
    }
}
--- user_files
>>> hello.lua
return function()
    return "hello", 200
end
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
        local ok, err = ngx.run_worker_thread("testpool", "hello")
        ngx.say(ok, " : ", err)
    }
}
--- user_files
>>> hello.lua
return function()
    ngx.sleep(1)
    return "ok"
end
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
        local ok, err = ngx.run_worker_thread("testpool", "hello")
        ngx.say(ok, " : ", err)
    }
}
--- request
GET /hello
--- response_body_like
false : module 'hello' not found.*
