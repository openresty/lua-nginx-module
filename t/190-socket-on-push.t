# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use Cwd qw(abs_path);

# Start a private TCP fixture on an OS-assigned loopback port. A separate
# control connection triggers pushes only after setkeepalive() has returned.
# No NATS installation, fixed ports, or timing-based server sleeps are needed.
our ($PushServer, $PushPid);
$PushPid = open $PushServer, '-|', 'python3', 't/lib/tcp-push-server.py'
    or die "cannot start TCP push server: $!";
my $port = <$PushServer>;
defined $port && $port =~ /^\d+\s*$/
    or die "TCP push server did not report its port";
chomp $port;
$ENV{TEST_NGINX_PUSH_PORT} = $port;
our $LuaLib = abs_path('t/lib');

END {
    if ($PushPid) {
        my $status = $?;
        kill 'TERM', $PushPid;
        close $PushServer;
        $? = $status;
    }
}

add_block_preprocessor(sub {
    my $block = shift;
    $block->set_value('main_config', 'env TEST_NGINX_PUSH_PORT;');
    $block->set_value('http_config', "lua_package_path '$LuaLib/?.lua;;';");
});

repeat_each(2);
no_long_string();
log_level('debug');
plan tests => repeat_each() * (blocks() * 5);
run_tests();

__DATA__

=== TEST 1: reply to an idle push and reuse the same connection
--- config
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            local received = ""
            local sock = t.connect("reply", function(data)
                received = received .. data
                if received == "PING\r\n" then
                    return "PONG\r\n", true
                end
                return nil, true
            end)
            assert(sock:setkeepalive(10000))
            t.command(control, "SEND", "reply", "PING\r\n")
            t.command(control, "EXPECT", "reply", "PONG\r\n")
            ngx.say("complete PING: ", received == "PING\r\n")
            assert(t.reuse("reply", control):close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
complete PING: true
reused: 1
--- no_error_log
[error]
[alert]
[crit]



=== TEST 2: nil reply keeps the connection open and preserves binary data
--- config
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            local expected = "hello\0world\255\r\n"
            local received = ""
            local sock = t.connect("binary", function(data)
                received = received .. data
                return nil, true
            end)
            assert(sock:setkeepalive(10000))
            t.command(control, "SEND", "binary", expected)
            t.wait(function() return #received >= #expected end)
            ngx.say("exact bytes: ", received == expected)
            assert(t.reuse("binary", control):close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
exact bytes: true
reused: 1
--- no_error_log
[error]
[alert]
[crit]



=== TEST 3: a single byte invokes the callback without closing the socket
--- config
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            local received = ""
            local sock = t.connect("single", function(data)
                received = received .. data
                return nil, true
            end)
            assert(sock:setkeepalive(10000))
            t.command(control, "SEND", "single", "X")
            t.wait(function() return #received > 0 end)
            ngx.say("received: ", received)
            assert(t.reuse("single", control):close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
received: X
reused: 1
--- no_error_log
[error]
[alert]
[crit]



=== TEST 4: a callback can assemble a message from separate read events
--- config
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            local received = ""
            local calls = 0
            local sock = t.connect("fragmented", function(data)
                calls = calls + 1
                received = received .. data
                if received == "PING\r\n" then
                    return "PONG\r\n", true
                end
                return nil, true
            end)
            assert(sock:setkeepalive(10000))
            t.command(control, "SEND", "fragmented", "P")
            t.wait(function() return received == "P" end)
            t.command(control, "SEND", "fragmented", "ING\r\n")
            t.command(control, "EXPECT", "fragmented", "PONG\r\n")
            ngx.say("multiple callbacks: ", calls >= 2)
            assert(t.reuse("fragmented", control):close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
multiple callbacks: true
reused: 1
--- no_error_log
[error]
[alert]
[crit]



=== TEST 5: drain a push larger than the callback buffer without losing bytes
--- config
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            local expected = string.rep("0123456789\0", 1000) .. "END"
            local received = ""
            local sock = t.connect("large", function(data)
                received = received .. data
                return nil, true
            end)
            assert(sock:setkeepalive(10000))
            t.command(control, "SEND", "large", expected)
            t.wait(function() return #received >= #expected end)
            ngx.say("exact bytes: ", received == expected)
            assert(t.reuse("large", control):close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
exact bytes: true
reused: 1
--- no_error_log
[error]
[alert]
[crit]



=== TEST 6: false sends the reply and closes the pooled connection
--- config
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            local sock = t.connect("close", function(data)
                return "BYE\r\n", false
            end)
            assert(sock:setkeepalive(10000))
            t.command(control, "SEND", "close", "STOP\r\n")
            t.command(control, "EXPECT", "close", "BYE\r\n")
            t.command(control, "CLOSED", "close")
            sock = t.connect("close")
            ngx.say("reused: ", sock:getreusedtimes())
            assert(sock:close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
reused: 0
--- no_error_log
[error]
[alert]
[crit]



=== TEST 7: a callback error closes the connection and leaves the worker usable
--- config
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            local sock = t.connect("error", function(data)
                error("deliberate on_push failure")
            end)
            assert(sock:setkeepalive(10000))
            t.command(control, "SEND", "error", "PUSH\r\n")
            t.command(control, "CLOSED", "error")
            sock = t.connect("error")
            ngx.say("reused: ", sock:getreusedtimes())
            assert(sock:close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
reused: 0
--- error_log
lua tcp socket keepalive callback error:
--- no_error_log
[alert]
[crit]



=== TEST 8: without a callback unsolicited data still closes the connection
--- config
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            local sock = t.connect("default")
            assert(sock:setkeepalive(10000))
            t.command(control, "SEND", "default", "PUSH\r\n")
            t.command(control, "CLOSED", "default")
            sock = t.connect("default")
            ngx.say("reused: ", sock:getreusedtimes())
            assert(sock:close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
reused: 0
--- no_error_log
[error]
[alert]
[crit]



=== TEST 9: EOF closes the pool item even with a callback
--- config
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            local calls = 0
            local callbacks = setmetatable({}, { __mode = "v" })
            callbacks[1] = function(data)
                calls = calls + 1
                return nil, true
            end
            local sock = t.connect("eof", callbacks[1])
            assert(sock:setkeepalive(10000))
            t.command(control, "CLOSE", "eof")
            -- Collection proves nginx observed EOF and released the callback.
            t.wait(function()
                collectgarbage()
                return callbacks[1] == nil
            end)
            sock = t.connect("eof")
            ngx.say("reused: ", sock:getreusedtimes())
            ngx.say("callbacks: ", calls)
            assert(sock:close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
reused: 0
callbacks: 0
--- no_error_log
[error]
[alert]
[crit]



=== TEST 10: checkout releases the old callback and re-pooling uses the new one
--- config
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            local callbacks = setmetatable({}, { __mode = "v" })
            callbacks[1] = function(data) return "OLD\r\n", true end
            local sock = t.connect("replace", callbacks[1])
            assert(sock:setkeepalive(10000))
            collectgarbage()
            ngx.say("pooled callback retained: ", callbacks[1] ~= nil)

            local received = ""
            sock = t.connect("replace", function(data)
                received = received .. data
                if received == "PUSH\r\n" then
                    return "NEW\r\n", true
                end
                return nil, true
            end)
            collectgarbage()
            collectgarbage()
            ngx.say("old callback released: ", callbacks[1] == nil)
            assert(sock:setkeepalive(10000))
            t.command(control, "SEND", "replace", "PUSH\r\n")
            t.command(control, "EXPECT", "replace", "NEW\r\n")
            ngx.say("new callback received: ", received == "PUSH\r\n")
            assert(t.reuse("replace", control):close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
pooled callback retained: true
old callback released: true
new callback received: true
reused: 2
--- no_error_log
[error]
[alert]
[crit]



=== TEST 11: callback survives completion of the request that pooled the socket
--- config
    location /park {
        content_by_lua_block {
            local t = require "socket-on-push"
            local state = { received = "" }
            t.finished_request = state
            local sock = t.connect("finished", function(data)
                state.received = state.received .. data
                if state.received == "PING\r\n" then
                    return "PONG\r\n", true
                end
                return nil, true
            end)
            assert(sock:setkeepalive(10000))
        }
    }
    location /t {
        content_by_lua_block {
            local t = require "socket-on-push"
            local control = t.control()
            assert(ngx.location.capture("/park").status == 200)
            collectgarbage()
            collectgarbage()
            t.command(control, "SEND", "finished", "PING\r\n")
            t.command(control, "EXPECT", "finished", "PONG\r\n")
            ngx.say("callback survived: ",
                    t.finished_request.received == "PING\r\n")
            assert(t.reuse("finished", control):close())
            assert(control:close())
        }
    }
--- request
GET /t
--- response_body
callback survived: true
reused: 1
--- no_error_log
[error]
[alert]
[crit]
