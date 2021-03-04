/*
 * Copyright (C) Jinhua Luo (kingluo)
 */

#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_worker_thread.h"
#include "ngx_http_lua_util.h"

#include <ngx_thread.h>
#include <ngx_thread_pool.h>

typedef struct task_ctx_s {
    lua_State* vm;
    ngx_thread_mutex_t mutex;
    struct task_ctx_s* next;
} task_ctx_t;

typedef struct {
    task_ctx_t* ctx;
    ngx_http_lua_co_ctx_t* wait_co_ctx;
    ngx_http_cleanup_pt cleanup;
    void* cleanup_data;
    int n_args;
    int rc;
    int is_abort;
} my_thread_ctx_t;

static task_ctx_t dummy_ctx;
static task_ctx_t* ctxpool = &dummy_ctx;

static task_ctx_t *
get_task_ctx(lua_State* L)
{
    task_ctx_t* ctx = NULL;
    if (ctxpool->next == NULL) {
        ctx = (task_ctx_t*)calloc(sizeof(task_ctx_t), 1);
        lua_State* vm = luaL_newstate();
        ctx->vm = vm;
        luaL_openlibs(ctx->vm);

        lua_getglobal(L, "package");
        lua_getglobal(vm, "package");

        // copy package.path
        lua_getfield(L, -1, "path");
        size_t path_len;
        const char* path = lua_tolstring(L, -1, &path_len);
        lua_pushlstring(vm, path, path_len);
        lua_setfield(vm, -2, "path");
        lua_pop(L, 1);

        // copy package.cpath
        lua_getfield(L, -1, "cpath");
        size_t cpath_len;
        const char* cpath = lua_tolstring(L, -1, &cpath_len);
        lua_pushlstring(vm, cpath, cpath_len);
        lua_setfield(vm, -2, "cpath");
        lua_pop(L, 1);

        // remove the "package" table
        lua_pop(L, 1);
        lua_pop(vm, 1);

        ngx_thread_mutex_create(&ctx->mutex, ngx_cycle->log);
    } else {
        ctx = ctxpool->next;
        ctxpool->next = ctxpool->next->next;
    }
    return ctx;
}

static void
put_task_ctx(task_ctx_t* ctx)
{
    ctx->next = ctxpool->next;
    ctxpool->next = ctx;
    /*  clear Lua stack */
    lua_settop(ctx->vm, 0);
}

static int
lauxh_xcopy(lua_State *from, lua_State *to, int idx, const int allow_nil)
{
    switch(lua_type(from, idx))
    {
        case LUA_TBOOLEAN:
            lua_pushboolean(to, lua_toboolean(from, idx));
            return LUA_TBOOLEAN;

        case LUA_TLIGHTUSERDATA:
            lua_pushlightuserdata(to, lua_touserdata(from, idx));
            return LUA_TLIGHTUSERDATA;

        case LUA_TNUMBER:
            lua_pushnumber(to, lua_tonumber(from, idx));
            return LUA_TNUMBER;

        case LUA_TSTRING: {
            size_t len = 0;
            const char *str = lua_tolstring(from, idx, &len);
            lua_pushlstring(to, str, len);
            return LUA_TSTRING;
        }

        case LUA_TTABLE:
            lua_newtable(to);
            // to positive number
            if(idx < 0) {
                idx = lua_gettop(from) + idx + 1;
            }
            lua_pushnil(from);
            while(lua_next(from, idx))
            {
                if(lauxh_xcopy(from, to, -2, 0) != LUA_TNONE)
                {
                    if(lauxh_xcopy(from, to, -1, 0) != LUA_TNONE) {
                        lua_rawset(to, -3);
                    }
                    else {
                        lua_pop(to, 1);
                    }
                }
                lua_pop(from, 1);
            }
            return LUA_TTABLE;

        case LUA_TNIL:
            if(allow_nil) {
                lua_pushnil(to);
                return LUA_TNIL;
            }
            // fall through

        // ignore unsupported values
        // LUA_TNONE
        // LUA_TFUNCTION
        // LUA_TUSERDATA
        // LUA_TTHREAD
        default:
            return LUA_TNONE;
    }
}

/* executed in a separate thread */
static void
my_thread_func(void *data, ngx_log_t *log)
{
    my_thread_ctx_t *ctx = data;
    lua_State *vm = ctx->ctx->vm;

    ctx->rc = lua_pcall(vm, ctx->n_args, LUA_MULTRET, 0);
}

/* executed in nginx event loop */
static void
my_thread_completion(ngx_event_t *ev)
{
    my_thread_ctx_t *myctx = ev->data;
    ngx_thread_mutex_lock(&myctx->ctx->mutex, ngx_cycle->log);
    int is_abort = myctx->is_abort;
    ngx_thread_mutex_unlock(&myctx->ctx->mutex, ngx_cycle->log);
    if (is_abort) {
        put_task_ctx(myctx->ctx);
        return;
    }

    lua_State* L = myctx->wait_co_ctx->co;

    ngx_http_request_t* r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        put_task_ctx(myctx->ctx);
        return;
    }
    ngx_connection_t* c = r->connection;

    ngx_http_lua_ctx_t *ctx;
    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        put_task_ctx(myctx->ctx);
        return;
    }

    lua_State *vm = myctx->ctx->vm;

    int nresults;
    if (myctx->rc != 0) {
        size_t len;
        const char* str = lua_tolstring(vm, 1, &len);
        lua_pushboolean(L, myctx->rc);
        lua_pushlstring(L, str, len);
        nresults = 2;
    } else {
        // copying return values
        lua_pushboolean(L, 1);
        nresults = lua_gettop(vm);
        for(int i = 1; i <= nresults; i++) {
            lauxh_xcopy(vm, L, i, 1);
        }
        nresults += 1;
    }

    put_task_ctx(myctx->ctx);

    // resume the caller coroutine

    myctx->wait_co_ctx->cleanup = myctx->cleanup;
    myctx->wait_co_ctx->data = myctx->cleanup_data;
    ctx->cur_co_ctx = myctx->wait_co_ctx;
    vm = ngx_http_lua_get_lua_vm(r, ctx);

    int rc = ngx_http_lua_run_thread(vm, r, ctx, nresults);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        ngx_http_lua_run_posted_threads(c, vm, r, ctx, c->requests);
        return;
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        ngx_http_lua_run_posted_threads(c, vm, r, ctx, c->requests);
        return;
    }

    /* rc == NGX_ERROR || rc >= NGX_OK */

    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return;
    }
}

static void
ngx_http_lua_worker_thread_cleanup(void *data)
{
    my_thread_ctx_t *ctx = data;
    ngx_thread_mutex_lock(&ctx->ctx->mutex, ngx_cycle->log);
    ctx->is_abort = 1;
    ngx_thread_mutex_unlock(&ctx->ctx->mutex, ngx_cycle->log);

    if (ctx->cleanup) {
        (ctx->cleanup)(ctx->cleanup_data);
    }
}

static int
ngx_http_lua_run_worker_thread(lua_State *L)
{
    ngx_http_request_t *r;
    int n_args;
    my_thread_ctx_t *myctx;
    ngx_thread_task_t *task;
    ngx_str_t thread_pool_name;
    ngx_thread_pool_t *thread_pool;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ngx_http_lua_ctx_t* ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    n_args = lua_gettop(L);
    if (n_args < 2) {
        return luaL_error(L, "expecting at least 2 arguments, but got %d", n_args);
    }

    thread_pool_name.data = (u_char*) lua_tolstring(L, 1, &thread_pool_name.len);
    thread_pool = ngx_thread_pool_get((ngx_cycle_t *) ngx_cycle, &thread_pool_name);
    if (thread_pool == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "thread_pool not found");
        return 2;
    }

    // get vm
    task_ctx_t* tctx = get_task_ctx(L);
    lua_State *vm = tctx->vm;

    // push function from module require
    size_t len;
    const char *mod_name = lua_tolstring(L, 2, &len);
    lua_getfield(vm, LUA_GLOBALSINDEX, "require");
    lua_pushlstring(vm, mod_name, len);
    int rc = lua_pcall(vm, 1, 1, 0);
    if (rc != 0) {
        size_t len;
        const char* err = lua_tolstring(vm, 1, &len);
        lua_pushboolean(L, 0);
        lua_pushlstring(L, err, len);
        put_task_ctx(tctx);
        return 2;
    }

    // copying passed arguments
    for(int i = 3; i <= n_args; i++) {
        lauxh_xcopy(L, vm, i, 1);
    }

    // post task
    task = ngx_thread_task_alloc(r->pool, sizeof(my_thread_ctx_t));
    if (task == NULL) {
        put_task_ctx(tctx);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "ngx_thread_task_alloc failed");
        return 2;
    }

    myctx = task->ctx;

    myctx->ctx = tctx;
    myctx->wait_co_ctx = ctx->cur_co_ctx;

    myctx->cleanup = ctx->cur_co_ctx->cleanup;
    myctx->cleanup_data = ctx->cur_co_ctx->data;

    ctx->cur_co_ctx->cleanup = ngx_http_lua_worker_thread_cleanup;
    ctx->cur_co_ctx->data = myctx;

    myctx->n_args = n_args - 2;
    myctx->rc = 0;
    myctx->is_abort = 0;

    task->handler = my_thread_func;
    task->event.handler = my_thread_completion;
    task->event.data = myctx;

    if (ngx_thread_task_post(thread_pool, task) != NGX_OK) {
        put_task_ctx(tctx);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "ngx_thread_task_post failed");
        return 2;
    }

    return lua_yield(L, 0);
}

void
ngx_http_lua_inject_worker_thread_api(ngx_log_t *log, lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_run_worker_thread);
    lua_setfield(L, -2, "run_worker_thread");
}
