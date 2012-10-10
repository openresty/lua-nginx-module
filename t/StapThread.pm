package t::StapThread;

use strict;
use warnings;

our $GCScript = <<'_EOC_';
global ids, cur
global in_req = 0

function gen_id(k) {
    if (ids[k]) return ids[k]
    ids[k] = ++cur
    return cur
}

F(ngx_http_init_request) {
    in_req++
    if (in_req == 1) {
        delete ids
        cur = 0
    }
}

F(ngx_http_free_request) {
    in_req--
}

M(http-lua-user-thread-spawn) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("spawn user thread %x in %x\n", c, p)
}

M(http-lua-thread-delete) {
    t = gen_id($arg2)
    printf("delete thread %x\n", t)
}

M(http-lua-user-coroutine-create) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("create %x in %x\n", c, p)
}

M(http-lua-coroutine-done) {
    t = gen_id($arg2)
    printf("terminate %d: %s\n", t, $arg3 ? "ok" : "fail")
    #print_ubacktrace()
}

_EOC_

our $StapScript = <<'_EOC_';
global ids, cur
global timers
global in_req = 0
global co_status

function gen_id(k) {
    if (ids[k]) return ids[k]
    ids[k] = ++cur
    return cur
}

F(ngx_http_init_request) {
    in_req++
    if (in_req == 1) {
        delete ids
        cur = 0
        co_status[0] = "running"
        co_status[1] = "suspended"
        co_status[2] = "normal"
        co_status[3] = "dead"
    }
}

F(ngx_http_free_request) {
    in_req--
}

F(ngx_http_lua_post_thread) {
    id = gen_id($coctx->co)
    printf("post thread %d\n", id)
}

M(timer-add) {
    timers[$arg1] = $arg2
    printf("add timer %d\n", $arg2)
}

M(timer-del) {
    printf("delete timer %d\n", timers[$arg1])
    delete timers[$arg1]
}

M(timer-expire) {
    printf("expire timer %d\n", timers[$arg1])
    delete timers[$arg1]
}

F(ngx_http_lua_sleep_handler) {
    printf("sleep handler called\n")
}

F(ngx_http_lua_run_thread) {
    id = gen_id($ctx->cur_co_ctx->co)
    printf("run thread %d\n", id)
    #if (id == 1) {
        #print_ubacktrace()
    #}
}

probe process("/usr/local/openresty-debug/luajit/lib/libluajit-5.1.so.2").function("lua_resume") {
    id = gen_id($L)
    printf("lua resume %d\n", id)
}

M(http-lua-user-thread-spawn) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("spawn uthread %x in %x\n", c, p)
}

M(http-lua-thread-delete) {
    t = gen_id($arg2)
    uthreads = @cast($arg3, "ngx_http_lua_ctx_t")->uthreads
    printf("delete thread %x (uthreads %d)\n", t, uthreads)
    #print_ubacktrace()
}

M(http-lua-run-posted-thread) {
    t = gen_id($arg2)
    printf("run posted thread %d (status %s)\n", t, co_status[$arg3])
}

M(http-lua-user-coroutine-resume) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("resume %x in %x\n", c, p)
}

M(http-lua-thread-yield) {
    t = gen_id($arg2)
    printf("thread %d yield\n", t)
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

F(ngx_http_lua_run_posted_threads) {
    printf("run posted threads\n")
}

F(ngx_http_finalize_request) {
    printf("finalize request: rc:%d c:%d\n", $rc, $r->main->count);
    #print_ubacktrace()
}

M(http-lua-user-coroutine-create) {
    p = gen_id($arg2)
    c = gen_id($arg3)
    printf("create %x in %x\n", c, p)
}

F(ngx_http_lua_ngx_exec) { println("exec") }

F(ngx_http_lua_ngx_exit) { println("exit") }

F(ngx_http_lua_req_body_cleanup) {
    println("lua req body cleanup")
}

F(ngx_http_read_client_request_body) {
    println("read client request body")
}

F(ngx_http_lua_finalize_coroutines) {
    println("finalize coroutines")
}

F(ngx_http_lua_ngx_exit) {
    println("ngx.exit() called")
}

F(ngx_http_lua_sleep_resume) {
    println("lua sleep resume")
}

M(http-lua-coroutine-done) {
    t = gen_id($arg2)
    printf("terminate coro %d: %s\n", t, $arg3 ? "ok" : "fail")
    //print_ubacktrace()
}

F(ngx_http_lua_ngx_echo) {
    println("ngx.print or ngx.say")
}

F(ngx_http_lua_del_all_threads) {
    println("del all threads")
}

/*
M(http-lua-info) {
    msg = user_string($arg1)
    printf("lua info: %s\n", msg)
}
*/

F(ngx_http_lua_uthread_wait) {
    t = gen_id($L)
    printf("lua thread %d waiting\n", t)
}
_EOC_

1;
