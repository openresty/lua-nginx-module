# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= '11211';

#no_shuffle();
no_long_string();
run_tests();

__DATA__

=== TEST 1: simple user thread wait without I/O
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.say("hello in thread")
                return "done"
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            local ok, res = ngx.thread.wait(t)
            if not ok then
                ngx.say("failed to run thread: ", res)
                return
            end

            ngx.say(res)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
hello in thread
thread created: zombie
done
--- no_error_log
[error]



=== TEST 2: simple user thread wait with I/O
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.sleep(0.1)
                ngx.say("hello in thread")
                return "done"
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            local ok, res = ngx.thread.wait(t)
            if not ok then
                ngx.say("failed to wait thread: ", res)
                return
            end

            ngx.say(res)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
thread created: running
hello in thread
done
--- no_error_log
[error]



=== TEST 3: wait on uthreads on the reversed order of their termination
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.sleep(0.1)
                ngx.say("f: hello")
                return "done"
            end

            function g()
                ngx.sleep(0.2)
                ngx.say("g: hello")
                return "done"
            end

            local tf, err = ngx.thread.spawn(f)
            if not tf then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("f thread created: ", coroutine.status(tf))

            local tg, err = ngx.thread.spawn(g)
            if not tg then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("g thread created: ", coroutine.status(tg))

            local ok, res = ngx.thread.wait(tg)
            if not ok then
                ngx.say("failed to wait g: ", res)
                return
            end

            ngx.say("g: ", res)

            ngx.say("f thread status: ", coroutine.status(tf))

            ok, res = ngx.thread.wait(tf)
            if not ok then
                ngx.say("failed to wait f: ", res)
                return
            end

            ngx.say("f: ", res)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
create 3 in 1
spawn user thread 3 in 1
terminate 2: ok
terminate 3: ok
delete thread 3
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
f thread created: running
g thread created: running
f: hello
g: hello
g: done
f thread status: zombie
f: done
--- no_error_log
[error]



=== TEST 4: wait on uthreads on the exact order of their termination
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.sleep(0.1)
                ngx.say("f: hello")
                return "done"
            end

            function g()
                ngx.sleep(0.2)
                ngx.say("g: hello")
                return "done"
            end

            local tf, err = ngx.thread.spawn(f)
            if not tf then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("f thread created: ", coroutine.status(tf))

            local tg, err = ngx.thread.spawn(g)
            if not tg then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("g thread created: ", coroutine.status(tg))

            ok, res = ngx.thread.wait(tf)
            if not ok then
                ngx.say("failed to wait f: ", res)
                return
            end

            ngx.say("f: ", res)

            ngx.say("g thread status: ", coroutine.status(tg))

            local ok, res = ngx.thread.wait(tg)
            if not ok then
                ngx.say("failed to wait g: ", res)
                return
            end

            ngx.say("g: ", res)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
create 3 in 1
spawn user thread 3 in 1
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3
terminate 1: ok
delete thread 1

--- response_body
f thread created: running
g thread created: running
f: hello
f: done
g thread status: running
g: hello
g: done
--- no_error_log
[error]



=== TEST 5: simple user thread wait without I/O (return multiple values)
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.say("hello in thread")
                return "done", 3.14
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            local ok, res1, res2 = ngx.thread.wait(t)
            if not ok then
                ngx.say("failed to run thread: ", res1)
                return
            end

            ngx.say("res: ", res1, " ", res2)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
hello in thread
thread created: zombie
res: done 3.14
--- no_error_log
[error]



=== TEST 6: simple user thread wait with I/O, return multiple values
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.sleep(0.1)
                ngx.say("hello in thread")
                return "done", 3.14
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            local ok, res1, res2 = ngx.thread.wait(t)
            if not ok then
                ngx.say("failed to wait thread: ", res1)
                return
            end

            ngx.say("res: ", res1, " ", res2)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
thread created: running
hello in thread
res: done 3.14
--- no_error_log
[error]



=== TEST 7: simple user thread wait without I/O, throw errors
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.say("hello in thread")
                error("bad bad!")
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            local ok, res = ngx.thread.wait(t)
            if not ok then
                ngx.say("failed to wait thread: ", res)
                return
            end

            ngx.say(res)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: fail
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
hello in thread
thread created: zombie
failed to wait thread: bad bad!
--- error_log
lua user thread aborted: runtime error: [string "content_by_lua"]:4: bad bad!



=== TEST 8: simple user thread wait with I/O, throw errors
--- config
    location /lua {
        content_by_lua '
            function f()
                ngx.sleep(0.1)
                ngx.say("hello in thread")
                error("bad bad!")
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            local ok, res = ngx.thread.wait(t)
            if not ok then
                ngx.say("failed to wait thread: ", res)
                return
            end

            ngx.say(res)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: fail
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
thread created: running
hello in thread
failed to wait thread: bad bad!
--- error_log
lua user thread aborted: runtime error: [string "content_by_lua"]:5: bad bad!



=== TEST 9: simple user thread wait without I/O (in a user coroutine)
--- config
    location /lua {
        content_by_lua '
            function g()
                ngx.say("hello in thread")
                return "done"
            end

            function f()
                local t, err = ngx.thread.spawn(g)
                if not t then
                    ngx.say("failed to spawn thread: ", err)
                    return
                end

                ngx.say("thread created: ", coroutine.status(t))

                collectgarbage()

                local ok, res = ngx.thread.wait(t)
                if not ok then
                    ngx.say("failed to run thread: ", res)
                    return
                end

                ngx.say(res)
            end

            local co = coroutine.create(f)
            coroutine.resume(co)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 2
spawn user thread 3 in 2
terminate 3: ok
delete thread 3
terminate 2: ok
terminate 1: ok
delete thread 1

--- response_body
hello in thread
thread created: zombie
done
--- no_error_log
[error]



=== TEST 10: simple user thread wait with I/O (in a user coroutine)
--- config
    location /lua {
        content_by_lua '
            function g()
                ngx.sleep(0.1)
                ngx.say("hello in thread")
                return "done"
            end

            function f()
                local t, err = ngx.thread.spawn(g)
                if not t then
                    ngx.say("failed to spawn thread: ", err)
                    return
                end

                ngx.say("thread created: ", coroutine.status(t))

                collectgarbage()

                local ok, res = ngx.thread.wait(t)
                if not ok then
                    ngx.say("failed to run thread: ", res)
                    return
                end

                ngx.say(res)
            end

            local co = coroutine.create(f)
            coroutine.resume(co)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 2
spawn user thread 3 in 2
terminate 3: ok
delete thread 3
terminate 2: ok
terminate 1: ok
delete thread 1

--- response_body
thread created: running
hello in thread
done
--- no_error_log
[error]

