# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use t::TestNginxLua;

repeat_each(2);

plan tests => repeat_each() * 108;

#$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';

no_long_string();

our $HtmlDir = html_dir;

check_accum_error_log();
run_tests();

__DATA__

=== TEST 1: code cache on by default
--- config
    location /lua {
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
32
--- no_error_log
[alert]



=== TEST 2: code cache explicitly on
--- config
    location /lua {
        lua_code_cache on;
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
32
--- no_error_log
[alert]



=== TEST 3: code cache explicitly off
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
101
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 4: code cache explicitly off (server level)
--- config
    lua_code_cache off;

    location /lua {
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
101
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 5: code cache explicitly off (server level) but be overridden in the location
--- config
    lua_code_cache off;

    location /lua {
        lua_code_cache on;
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
32
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 6: code cache explicitly off (affects require) + content_by_lua
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua '
            local foo = require "foo";
        ';
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/foo.lua", "w"))
            f:write("module(..., package.seeall); ngx.say(102);")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> foo.lua
module(..., package.seeall); ngx.say(32);
--- request
GET /main
--- response_body
32
updated
102
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 7: code cache explicitly off (affects require) + content_by_lua_file
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/foo.lua", "w"))
            f:write("module(..., package.seeall); ngx.say(102);")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
local foo = require "foo";
>>> foo.lua
module(..., package.seeall); ngx.say(32);
--- request
GET /main
--- response_body
32
updated
102
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 8: code cache explicitly off (affects require) + set_by_lua_file
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    location /lua {
        lua_code_cache off;
        set_by_lua_file $a html/test.lua;
        echo $a;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/foo.lua", "w"))
            f:write("module(..., package.seeall); return 102;")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
return require "foo"
>>> foo.lua
module(..., package.seeall); return 32;
--- request
GET /main
--- response_body
32
updated
102
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 9: code cache explicitly on (affects require) + set_by_lua_file
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    location /lua {
        lua_code_cache on;
        set_by_lua_file $a html/test.lua;
        echo $a;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/foo.lua", "w"))
            f:write("module(..., package.seeall); return 102;")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
return require "foo"
>>> foo.lua
module(..., package.seeall); return 32;
--- request
GET /main
--- response_body
32
updated
32
--- no_error_log
[alert]



=== TEST 10: code cache explicitly off + set_by_lua_file
--- config
    location /lua {
        lua_code_cache off;
        set_by_lua_file $a html/test.lua;
        echo $a;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("return 101")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
return 32
--- request
GET /main
--- response_body
32
updated
101
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 11: code cache explicitly on + set_by_lua_file
--- config
    location /lua {
        lua_code_cache on;
        set_by_lua_file $a html/test.lua;
        echo $a;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("return 101")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
return 32
--- request
GET /main
--- response_body
32
updated
32
--- no_error_log
[alert]



=== TEST 12: no clear builtin lib "string"
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua_file html/test.lua;
    }
    location /main {
        echo_location /lua;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(string.len("hello"))
ngx.say(table.concat({1,2,3}, ", "))
--- request
    GET /main
--- response_body
5
1, 2, 3
5
1, 2, 3
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 13: no clear builtin lib "string"
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua '
            ngx.say(string.len("hello"))
            ngx.say(table.concat({1,2,3}, ", "))
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /lua;
    }
--- request
    GET /main
--- response_body
5
1, 2, 3
5
1, 2, 3
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 14: no clear builtin lib "string"
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    lua_code_cache off;
    location /lua {
        content_by_lua '
            local test = require("test")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /lua;
    }
--- request
    GET /main
--- user_files
>>> test.lua
module("test", package.seeall)

string = require("string")
math = require("math")
io = require("io")
os = require("os")
table = require("table")
coroutine = require("coroutine")
package = require("package")
ngx.say("OK")
--- response_body
OK
OK
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 15: do not skip luarocks
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';
     lua_code_cache off;"
--- config
    location /main {
        echo_location /load;
        echo_location /check;
        echo_location /check;
    }

    location /load {
        content_by_lua '
            package.loaded.luarocks = nil;
            local foo = require "luarocks";
            foo.hi()
        ';
    }

    location /check {
        content_by_lua '
            local foo = package.loaded.luarocks
            if foo then
                ngx.say("found")
            else
                ngx.say("not found")
            end
        ';
    }
--- request
GET /main
--- user_files
>>> luarocks.lua
module(..., package.seeall);

ngx.say("loading");

function hi ()
    ngx.say("hello, foo")
end;
--- response_body
loading
hello, foo
not found
not found
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 16: do not skip luarocks*
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';
     lua_code_cache off;"
--- config
    location /main {
        echo_location /load;
        echo_location /check;
        echo_location /check;
    }

    location /load {
        content_by_lua '
            package.loaded.luarocks2 = nil;
            local foo = require "luarocks2";
            foo.hi()
        ';
    }

    location /check {
        content_by_lua '
            local foo = package.loaded.luarocks2
            if foo then
                ngx.say("found")
            else
                ngx.say("not found")
            end
        ';
    }
--- request
GET /main
--- user_files
>>> luarocks2.lua
module(..., package.seeall);

ngx.say("loading");

function hi ()
    ngx.say("hello, foo")
end;
--- response_body
loading
hello, foo
not found
not found
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 17: clear _G table
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    lua_code_cache off;
    location /t {
        content_by_lua '
            if not _G.foo then
                _G.foo = 1
            else
                _G.foo = _G.foo + 1
            end
            ngx.say("_G.foo: ", _G.foo)
        ';
    }
--- request
    GET /t
--- response_body
_G.foo: 1
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 18: github #257: globals cleared when code cache off
--- http_config
    lua_code_cache off;
    init_by_lua '
      test = setfenv(
        function()
          ngx.say(tostring(table))
        end,
        setmetatable({},
        {
          __index = function(self, key)
          return rawget(self, key) or _G[key]
        end
      }))';
--- config
    location = /t {
        content_by_lua 'test()';
    }
--- request
GET /t
--- response_body_like chop
^table: 0x\d*?[1-9a-fA-F]
--- no_error_log
[error]
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 19: lua_code_cache off + FFI-based Lua modules
--- http_config
    lua_code_cache off;
    lua_package_path "$prefix/html/?.lua;;";

--- config
    location = /t {
        content_by_lua '
            if not jit then
                ngx.say("skipped for non-LuaJIT")
            else
                local test = require("test")
                ngx.say("test module loaded: ", test and true or false)
                collectgarbage()
            end
        ';
    }
--- user_files
>>> test.lua
local ffi = require "ffi"

ffi.cdef[[
    int my_test_function_here(void *p);
    int my_test_function_here2(void *p);
    int my_test_function_here3(void *p);
]]

return {
}
--- request
GET /t
--- response_body_like chop
^(?:skipped for non-LuaJIT|test module loaded: true)$
--- no_error_log
[error]
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/



=== TEST 20: ngx.timer.* + ndk
--- config
    lua_code_cache off;
    location /read {
        echo ok;
        log_by_lua '
            ngx.timer.at(0, function ()
                local foo = ndk.set_var.set_unescape_uri("a%20b")
                ngx.log(ngx.WARN, "foo = ", foo)
            end)
        ';
    }
--- request
GET /read
--- response_body
ok
--- wait: 0.1
--- no_error_log
[error]
--- error_log eval
["foo = a b",
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/
]



=== TEST 21: set ngx.ctx before internal redirects performed by other nginx modules (with log_by_lua)
--- config
    lua_code_cache off;
    location = /t {
        rewrite_by_lua '
            ngx.ctx.foo = "hello world";
        ';
        echo_exec /foo;
    }

    location = /foo {
        echo hello;
        log_by_lua return;
    }
--- request
GET /t
--- response_body
hello
--- no_error_log
[error]
--- log_level: debug
--- error_log eval
["lua release ngx.ctx at ref",
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/,
"lua close the global Lua VM",
]



=== TEST 22: set by lua file
--- config
    lua_code_cache off;
    location /lua {
        set_by_lua_file $res html/a.lua $arg_a $arg_b;
        echo $res;
    }
--- user_files
>>> a.lua
return ngx.arg[1] + ngx.arg[2]
--- request
GET /lua?a=5&b=2
--- response_body
7
--- no_error_log
[error]
--- error_log eval
[qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/,
"lua close the global Lua VM",
]



=== TEST 23: simple set by lua
--- config
    lua_code_cache off;
    location /lua {
        set_by_lua $res "return 1+1";
        echo $res;
    }
--- request
GET /lua
--- response_body
2
--- no_error_log
[error]
--- error_log eval
[
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/,
"lua close the global Lua VM",
]



=== TEST 24: lua_max_pending_timers - chained timers (non-zero delay) - not exceeding
--- http_config
    lua_max_pending_timers 1;
    lua_code_cache off;

--- config
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local function g()
                s = s .. "[g]"
                print("trace: ", s)
            end

            local function f()
                local ok, err = ngx.timer.at(0.01, g)
                if not ok then
                    fail("failed to set timer: ", err)
                    return
                end
                s = s .. "[f]"
            end
            local ok, err = ngx.timer.at(0.01, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
create 3 in 2
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[error]
--- error_log eval
[
"lua ngx.timer expired",
"http lua close fake http connection",
"trace: [m][f][g]",
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/,
"lua close the global Lua VM",
]



=== TEST 25: lua variable sharing via upvalue
--- http_config
    lua_code_cache off;
--- config
    location /t {
        content_by_lua '
            local begin = ngx.now()
            local foo
            local function f()
                foo = 3
                print("elapsed: ", ngx.now() - begin)
            end
            local ok, err = ngx.timer.at(0.05, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.say("registered timer")
            ngx.sleep(0.06)
            ngx.say("foo = ", foo)
        ';
    }
--- request
GET /t
--- stap2
F(ngx_http_lua_timer_handler) {
    println("lua timer handler")
}

--- response_body
registered timer
foo = 3

--- wait: 0.1
--- no_error_log
[error]

--- error_log eval
[
qr/\[lua\] \[string "content_by_lua"\]:\d+: elapsed: 0\.0(?:4[4-9]|5[0-6])/,
"lua ngx.timer expired",
"http lua close fake http connection",
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/,
"lua close the global Lua VM",
]



=== TEST 26: lua_max_running_timers (just not enough)
--- http_config
    lua_max_running_timers 1;
--- config
    lua_code_cache off;
    location /t {
        content_by_lua '
            local s = ""

            local function fail(...)
                ngx.log(ngx.ERR, ...)
            end

            local f, g

            g = function ()
                ngx.sleep(0.01)
            end

            f = function ()
                ngx.sleep(0.01)
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to set timer f: ", err)
                return
            end
            local ok, err = ngx.timer.at(0, g)
            if not ok then
                ngx.say("failed to set timer g: ", err)
                return
            end
            ngx.say("registered timer")
            s = "[m]"
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
registered timer

--- wait: 0.1
--- no_error_log
[crit]
[error]

--- error_log eval
[
"1 lua_max_running_timers are not enough",
"lua ngx.timer expired",
"http lua close fake http connection",
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/
]



=== TEST 27: GC issue with the on_abort thread object
--- config
    lua_code_cache off;
    location = /t {
        lua_check_client_abort on;
        content_by_lua '
            ngx.on_abort(function () end)
            collectgarbage()
            ngx.sleep(1)
        ';
    }
--- request
    GET /t
--- abort
--- timeout: 0.2
--- wait: 1
--- ignore_response
--- no_error_log
[error]
--- error_log eval
qr/\[alert\] \S+ lua_code_cache is off; this will hurt performance/

