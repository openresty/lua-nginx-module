# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 3 + 9);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: set a global lua var
--- http_config
    init_worker_by_lua '
        foo = ngx.md5("hello world")
    ';
--- config
    location /t {
        content_by_lua '
            ngx.say("foo = ", foo)
        ';
    }
--- request
    GET /t
--- response_body
foo = 5eb63bbbe01eeed093cb22bb8f5acdc3
--- no_error_log
[error]



=== TEST 2: no ngx.say()
--- http_config
    init_worker_by_lua '
        ngx.say("hello")
    ';
--- config
    location /t {
        content_by_lua '
            ngx.say("foo = ", foo)
        ';
    }
--- request
    GET /t
--- response_body
foo = nil
--- error_log
API disabled in the context of init_worker_by_lua*



=== TEST 3: timer.at
--- http_config
    init_worker_by_lua '
        _G.my_counter = 0
        local function warn(...)
            ngx.log(ngx.WARN, ...)
        end
        local function handler(premature)
            warn("timer expired (premature: ", premature, "; counter: ",
                 _G.my_counter, ")")
            _G.my_counter = _G.my_counter + 1
        end
        local ok, err = ngx.timer.at(0, handler)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
        end
        warn("created timer: ", ok)
    ';
--- config
    location /t {
        content_by_lua '
            -- ngx.sleep(0.001)
            ngx.say("my_counter = ", _G.my_counter)
            _G.my_counter = _G.my_counter + 1
        ';
    }
--- request
    GET /t
--- response_body
my_counter = 1
--- grep_error_log eval: qr/warn\(\): [^,]*/
--- grep_error_log_out
warn(): created timer: 1
warn(): timer expired (premature: false; counter: 0)

--- no_error_log
[error]



=== TEST 4: timer.at + cosocket
--- http_config
    init_worker_by_lua '
        _G.done = false
        local function warn(...)
            ngx.log(ngx.WARN, ...)
        end
        local function error(...)
            ngx.log(ngx.ERR, ...)
        end
        local function handler(premature)
            warn("timer expired (premature: ", premature, ")")

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                error("failed to connect: ", err)
                _G.done = true
                return
            end

            local req = "flush_all\\r\\n"

            local bytes, err = sock:send(req)
            if not bytes then
                error("failed to send request: ", err)
                _G.done = true
                return
            end

            warn("request sent: ", bytes)

            local line, err, part = sock:receive()
            if line then
                warn("received: ", line)
            else
                error("failed to receive a line: ", err, " [", part, "]")
            end
            _G.done = true
        end

        local ok, err = ngx.timer.at(0, handler)
        if not ok then
            error("failed to create timer: ", err)
        end
        warn("created timer: ", ok)
    ';
--- config
    location = /t {
        content_by_lua '
            local waited = 0
            local sleep = ngx.sleep
            while not _G.done do
                local delay = 0.001
                sleep(delay)
                waited = waited + delay
                if waited > 1 then
                    ngx.say("timed out")
                    return
                end
            end
            ngx.say("ok")
        ';
    }
--- request
    GET /t
--- response_body
ok
--- grep_error_log eval: qr/warn\(\): [^,]*/
--- grep_error_log_out
warn(): created timer: 1
warn(): timer expired (premature: false)
warn(): request sent: 11
warn(): received: OK

--- log_level: debug
--- error_log
lua tcp socket connect timeout: 60000
lua tcp socket send timeout: 60000
lua tcp socket read timeout: 60000
--- no_error_log
[error]



=== TEST 5: init_worker_by_lua_file (simple global var)
--- http_config
    init_worker_by_lua_file html/foo.lua;
--- config
    location /t {
        content_by_lua '
            ngx.say("foo = ", foo)
        ';
    }
--- user_files
>>> foo.lua
foo = ngx.md5("hello world")
--- request
    GET /t
--- response_body
foo = 5eb63bbbe01eeed093cb22bb8f5acdc3
--- no_error_log
[error]



=== TEST 6: timer.at + cosocket (by_lua_file)
--- main_config
env TEST_NGINX_MEMCACHED_PORT;
--- http_config
    init_worker_by_lua_file html/foo.lua;
--- user_files
>>> foo.lua
_G.done = false
local function warn(...)
    ngx.log(ngx.WARN, ...)
end
local function error(...)
    ngx.log(ngx.ERR, ...)
end
local function handler(premature)
    warn("timer expired (premature: ", premature, ")")

    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("127.0.0.1",
                                 os.getenv("TEST_NGINX_MEMCACHED_PORT"))
    if not ok then
        error("failed to connect: ", err)
        _G.done = true
        return
    end

    local req = "flush_all\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        error("failed to send request: ", err)
        _G.done = true
        return
    end

    warn("request sent: ", bytes)

    local line, err, part = sock:receive()
    if line then
        warn("received: ", line)
    else
        error("failed to receive a line: ", err, " [", part, "]")
    end
    _G.done = true
end

local ok, err = ngx.timer.at(0, handler)
if not ok then
    error("failed to create timer: ", err)
end
warn("created timer: ", ok)

--- config
    location = /t {
        content_by_lua '
            local waited = 0
            local sleep = ngx.sleep
            while not _G.done do
                local delay = 0.001
                sleep(delay)
                waited = waited + delay
                if waited > 1 then
                    ngx.say("timed out")
                    return
                end
            end
            ngx.say("ok")
        ';
    }
--- request
    GET /t
--- response_body
ok
--- grep_error_log eval: qr/warn\(\): [^,]*/
--- grep_error_log_out
warn(): created timer: 1
warn(): timer expired (premature: false)
warn(): request sent: 11
warn(): received: OK

--- log_level: debug
--- error_log
lua tcp socket connect timeout: 60000
lua tcp socket send timeout: 60000
lua tcp socket read timeout: 60000
--- no_error_log
[error]

