# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * blocks() * 5;

log_level 'debug';
worker_connections(256);
no_long_string();

$ENV{TEST_NGINX_HTML_DIR} = html_dir();

# Keep the regular CI run short. Increase this for repeated cancellation and
# pool teardown in one worker, for example TEST_NGINX_SOCKET_POOL_ROUNDS=300.
our $Rounds = $ENV{TEST_NGINX_SOCKET_POOL_ROUNDS} // 5;
die "TEST_NGINX_SOCKET_POOL_ROUNDS must be a positive integer\n"
    unless $Rounds =~ /\A[1-9][0-9]*\z/;

our $StressTimeout = 10 + $Rounds;
our $HttpVersion = $ENV{TEST_NGINX_USE_HTTP3} ? 3
                  : $ENV{TEST_NGINX_USE_HTTP2} ? 2 : 1.1;

our $Helpers = <<'_EOC_';
>>> queue.lua
local port = ngx.var.server_port
local phase = ngx.get_phase()
assert(phase == ngx.var.expected_phase, phase)
assert(ngx.req.http_version() == tonumber(ngx.var.expected_version))


local function check_full(opts)
    local extra = ngx.socket.tcp()
    extra:settimeout(20)
    local ok, err = extra:connect("127.0.0.1", port, opts)
    assert(not ok and err == "timeout", err)
end


local function run_handoff(name, cancel, close)
    local opts = {pool = phase .. name, pool_size = 1, backlog = 3}
    local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
    local pending = ngx.socket.tcp()
    pending:settimeout(1000)
    local first = ngx.thread.spawn(function()
        assert(pending:connect("127.0.0.1", port, opts))
        assert(not cancel, "cancelled waiter resumed")
        local reused = pending:getreusedtimes()
        assert(pending:setkeepalive())
        return reused
    end)
    local second = ngx.thread.spawn(function()
        local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
        local reused = sock:getreusedtimes()
        assert(sock:setkeepalive())
        return reused
    end)

    if close then
        assert(holder:close())

    else
        assert(holder:setkeepalive())
    end

    local other = {pool = phase .. "other", pool_size = 1, backlog = 1}
    local ok, err = pending:connect("127.0.0.1", port, other)
    assert(not ok and err == "socket busy connecting", err)

    if cancel then
        assert(ngx.thread.kill(first))
    end

    collectgarbage("collect")

    -- This connect must queue behind the remaining operation, including
    -- when the cancelled operation owned an empty slot instead of a peer.
    local sock = assert(ngx.socket.connect("127.0.0.1", port, opts))
    local reused = sock:getreusedtimes()
    local ok, second_reused = ngx.thread.wait(second)
    assert(ok, second_reused)

    if not cancel then
        local ok, first_reused = ngx.thread.wait(first)
        assert(ok, first_reused)
        ngx.say(name, ": ", first_reused, ", ", second_reused, ", ", reused)

    else
        ngx.say(name, ": ", second_reused, ", ", reused)
    end

    check_full(opts)
    assert(sock:close())

    -- Both a consumed connect and a cancelled connect leave a reusable
    -- socket object. The old pool has no remaining connection at this point.
    assert(pending:connect("127.0.0.1", port, opts))
    assert(pending:getreusedtimes() == 0)
    assert(pending:close())
end


ngx.say("phase: ", phase)
run_handoff("handoff", false, false)
run_handoff("cancel handoff", true, false)
run_handoff("cancel empty", true, true)

local opts = {pool = phase .. "timeout", pool_size = 1, backlog = 1}
local holder = assert(ngx.socket.connect("127.0.0.1", port, opts))
local sock = ngx.socket.tcp()
sock:settimeout(20)
local ok, err = sock:connect("127.0.0.1", port, opts)
assert(not ok and err == "timeout", err)
assert(holder:close())
sock:settimeout(1000)
assert(sock:connect("127.0.0.1", port, opts))
ngx.say("timeout retry: ", sock:getreusedtimes())
assert(sock:close())

>>> stress.lua
local rounds = tonumber(ngx.var.rounds)
local port = ngx.var.server_port
local seed = 2544990
local completed, queued, posted, saturated, gc = 0, 0, 0, 0, 0
local all_posted_cancelled = 0
assert(ngx.req.http_version() == tonumber(ngx.var.expected_version))


local function random(n)
    seed = (seed * 1664525 + 1013904223) % 4294967296
    return (seed % n) + 1
end


local function full_gc()
    collectgarbage("collect")
    gc = gc + 1
end


local function waiter(state, i, opts, round)
    local sock = ngx.socket.tcp()
    sock:settimeout(2000)
    assert(sock:connect("127.0.0.1", port, opts))
    state.live = state.live + 1
    assert(state.live <= opts.pool_size, "too many active peers")

    if i % 3 == 0 then
        ngx.sleep(0)
    end

    state.live = state.live - 1

    if (i + round) % 2 == 0 then
        assert(sock:setkeepalive())

    else
        assert(sock:close())
    end

    state.completed[i] = true
    completed = completed + 1
    return true
end


local function cancel(state, i, assigned)
    if state.cancelled[i] then
        return
    end

    assert(ngx.thread.kill(state.threads[i]))
    state.cancelled[i] = true

    if assigned then
        posted = posted + 1

    else
        queued = queued + 1
    end
end


for size = 1, 3 do
    local opts = {pool = "stress" .. size, pool_size = size,
                  backlog = 4 * size + 4}

    for round = 1, rounds do
        local state = {live = size, threads = {}, cancelled = {},
                       completed = {}}
        local holders = {}
        local mode = (round - 1) % 5
        local count = 2 * size + 3

        for i = 1, size do
            holders[i] = assert(ngx.socket.connect("127.0.0.1", port, opts))
        end

        for i = 1, count do
            state.threads[i] = ngx.thread.spawn(waiter, state, i, opts, round)
        end

        if mode == 0 then
            cancel(state, size + 1, false)

        elseif mode == 3 then
            for i = size + 1, count do
                if random(3) == 1 then
                    cancel(state, i, false)
                end
            end
        end

        full_gc()

        -- No yielding between handing out slots and cancelling their owners.
        for i = 1, size do
            state.live = state.live - 1

            if mode == 1 or (mode ~= 2 and random(2) == 1) then
                assert(holders[i]:setkeepalive())

            else
                assert(holders[i]:close())
            end
        end

        if mode == 1 or mode == 2 then
            for i = 1, size do
                cancel(state, i, true)
            end

            all_posted_cancelled = all_posted_cancelled + 1

        elseif mode == 3 then
            for i = 1, size do
                if random(2) == 1 then
                    cancel(state, i, true)
                end
            end

        elseif mode == 4 then
            cancel(state, random(size), true)
            cancel(state, size + 1 + random(count - size - 1), false)
        end

        full_gc()

        for i = 1, count do
            if state.cancelled[i] then
                assert(not state.completed[i], "cancelled waiter ran")

            else
                local ok, res = ngx.thread.wait(state.threads[i])
                assert(ok and res == true, res)
                assert(state.completed[i], "waiter did not finish")
            end
        end

        assert(state.live == 0, "active peer left behind")

        local final = {}

        for i = 1, size do
            local sock = ngx.socket.tcp()
            sock:settimeout(1000)
            assert(sock:connect("127.0.0.1", port, opts))
            final[i] = sock
        end

        local extra = ngx.socket.tcp()
        extra:settimeout(5)
        local ok, err = extra:connect("127.0.0.1", port, opts)
        assert(not ok and err == "timeout", "excess peer admitted")
        saturated = saturated + 1

        for i = 1, size do
            if round % 2 == 0 then
                assert(final[i]:close())

            else
                assert(final[i]:setkeepalive())
            end
        end

        -- Drop dead threads and their sockets before forcing collection.
        state = nil
        holders = nil
        final = nil
        full_gc()
    end
end

assert(saturated == 3 * rounds)
assert(gc == 9 * rounds)
assert(completed + queued + posted == 21 * rounds)

if rounds >= 5 then
    assert(queued > 0 and posted > 0 and all_posted_cancelled > 0)
end

ngx.say("rounds: ", saturated)
ngx.say("gc: ", gc)
ngx.say("all waiters accounted for")
_EOC_

add_block_preprocessor(sub {
    my $block = shift;

    $block->set_value("user_files", $Helpers);
});

run_tests();

__DATA__

=== TEST 1: queued connects resume, cancel and time out in rewrite
--- config eval
    qq{
        location /t {
            lua_socket_log_errors off;
            set \$expected_phase rewrite;
            set \$expected_version $::HttpVersion;
            rewrite_by_lua_file html/queue.lua;
            content_by_lua_block { }
        }
    }
--- request
GET /t
--- response_body
phase: rewrite
handoff: 1, 2, 3
cancel handoff: 1, 2
cancel empty: 0, 1
timeout retry: 0
--- no_error_log
[error]
[alert]
[crit]



=== TEST 2: queued connects resume, cancel and time out in access
--- config eval
    qq{
        location /t {
            lua_socket_log_errors off;
            set \$expected_phase access;
            set \$expected_version $::HttpVersion;
            access_by_lua_file html/queue.lua;
            content_by_lua_block { }
        }
    }
--- request
GET /t
--- response_body
phase: access
handoff: 1, 2, 3
cancel handoff: 1, 2
cancel empty: 0, 1
timeout retry: 0
--- no_error_log
[error]
[alert]
[crit]



=== TEST 3: queued connects resume, cancel and time out in content
--- config eval
    qq{
        location /t {
            lua_socket_log_errors off;
            set \$expected_phase content;
            set \$expected_version $::HttpVersion;
            content_by_lua_file html/queue.lua;
        }
    }
--- request
GET /t
--- response_body
phase: content
handoff: 1, 2, 3
cancel handoff: 1, 2
cancel empty: 0, 1
timeout retry: 0
--- no_error_log
[error]
[alert]
[crit]



=== TEST 4: repeated cancellation preserves capacity across pool lifetimes
--- config eval
    qq{
        location /t {
            lua_socket_log_errors off;
            set \$rounds $::Rounds;
            set \$expected_version $::HttpVersion;
            content_by_lua_file html/stress.lua;
        }
    }
--- request
GET /t
--- response_body eval
    "rounds: " . (3 * $::Rounds) . "\ngc: " . (9 * $::Rounds)
    . "\nall waiters accounted for\n"
--- no_error_log
[error]
[alert]
[crit]
--- timeout eval: $::StressTimeout
--- quic_max_idle_timeout eval: $::StressTimeout
