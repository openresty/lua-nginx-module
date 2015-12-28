

/**
 * Copyright (C) Terry AN (anhk)
 **/

#include "ddebug.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_lfs.h"

#if (NGX_THREADS)


typedef struct _ngx_http_lua_lfs_task_ctx_s {
    lua_State *L;
    ngx_http_request_t *r;
    u_char *filename;
    ssize_t size;
    off_t offset;
    u_char *buff;
} ngx_http_lua_lfs_task_ctx_t;


typedef void (*task_callback)(void *data, ngx_log_t *log);
typedef void (*event_callback)(ngx_event_t *ev);

typedef struct _ngx_http_lua_lfs_ops_s {
    task_callback task_callback;
    event_callback event_callback;
} ngx_http_lua_lfs_ops_t;

enum {
    TASK_READ = 0,
    TASK_WRITE,
} TASK_OPS;


static ngx_int_t ngx_http_lua_lfs_resume(ngx_http_request_t *r)
{
    lua_State *vm;
    ngx_connection_t *c;
    ngx_int_t rc;
    ngx_http_lua_ctx_t *ctx;
    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }    

    ctx->resume_handler = ngx_http_lua_wev_handler;

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);

    rc = ngx_http_lua_run_thread(vm, r, ctx, 1);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua run thread returned %d", rc); 

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx);
    }    

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx);
    }    

    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc); 
        return NGX_DONE;
    }    

    return rc;
}

static void ngx_http_lua_lfs_event_handler(ngx_event_t *ev)
{
    ngx_connection_t        *c;
    ngx_http_request_t      *r;
    ngx_http_lua_ctx_t      *ctx;
    ngx_http_log_ctx_t      *log_ctx;
    ngx_http_lua_co_ctx_t   *coctx;

    coctx = ev->data;

    r = coctx->data;
    c = r->connection;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        return;
    }

    if (c->fd != -1) {  /* not a fake connection */
        log_ctx = c->log->data;
        log_ctx->current_request = r;
    }

    coctx->cleanup = NULL;

    ctx->cur_co_ctx = coctx;

    if (ctx->entered_content_phase) {
        (void) ngx_http_lua_lfs_resume(r);

    } else {
        ctx->resume_handler = ngx_http_lua_lfs_resume;
        ngx_http_core_run_phases(r);
    }

    ngx_http_run_posted_requests(c);
}


void ngx_http_lua_lfs_task_read(void *data, ngx_log_t *log)
{
}

void ngx_http_lua_lfs_task_read_event(ngx_event_t *ev)
{
    ngx_http_lua_lfs_task_ctx_t *task_ctx = ev->data;
    ngx_http_request_t *r = task_ctx->r;

    r->main->blocked --;
    r->aio = 0;

    lua_pushlstring(task_ctx->L, "From LFS", strlen("From LFS"));
    ngx_http_lua_lfs_event_handler(ev);
}

void ngx_http_lua_lfs_task_write(void *data, ngx_log_t *log)
{
}

void ngx_http_lua_lfs_task_write_event(ngx_event_t *ev)
{
}

static ngx_http_lua_lfs_ops_t lfs_ops[] = {
    { /** TASK_READ **/
        .task_callback = ngx_http_lua_lfs_task_read,
        .event_callback = ngx_http_lua_lfs_task_read_event,
    },
    { /** TASK_WRITE **/
        .task_callback = ngx_http_lua_lfs_task_write,
        .event_callback = ngx_http_lua_lfs_task_write_event,
    }
};

/**
 * create task
 **/
static ngx_thread_task_t *ngx_http_lua_lfs_create_task(ngx_pool_t *pool, int ops)
{
    ngx_thread_task_t *task;

    if ((task = ngx_thread_task_alloc(pool, 
                    sizeof(ngx_http_lua_lfs_task_ctx_t))) == NULL) {
        return NULL;
    }

    task->handler = lfs_ops[ops].task_callback;
    task->event.data = task->ctx;
    task->event.handler = lfs_ops[ops].event_callback;

    return task;
}

static int ngx_http_lua_lfs_post_task(ngx_thread_task_t *task)
{
    ngx_thread_pool_t *pool;
    ngx_str_t poolname = ngx_string("luafs");

    if ((pool = ngx_thread_pool_get((ngx_cycle_t*) ngx_cycle, &poolname)) == NULL) {
        return -1;
    }

    if (ngx_thread_task_post(pool, task) != NGX_OK) {
        return -1;
    }

    return 0;
}

/**
 * ngx.lfs.read("/root/1.txt", size, offset)
 **/
static int ngx_http_lua_ngx_lfs_read(lua_State *L)
{
    int n;
    ssize_t size;
    off_t offset;
    ngx_http_request_t *r;
    ngx_http_lua_lfs_task_ctx_t *task_ctx;
    ngx_thread_task_t *task;
    ngx_str_t str;

    n = lua_gettop(L);
    if (n < 1 && n > 3) {
        return luaL_error(L, "expected 1, 2 or 3 arguments, but seen %d", n);
    }

    if (!lua_isstring(L, 1)) {
        return luaL_error(L, "string expected, argument 1");
    }

    str.data = (u_char*) lua_tolstring(L, 1, &str.len);
    if (str.len <= 0) {
        return luaL_error(L, "bad argument 1");
    }

    if (n == 1) { /** n < 2 **/
        size = 65536;
        offset = 0;
    } else if (n == 2) {
        size = (ssize_t) luaL_checknumber(L, 2);
        offset = 0;
    } else {
        size = (ssize_t) luaL_checknumber(L, 2);
        offset = (off_t)  luaL_checknumber(L, 3);
    }

    if (size < 0 || offset < 0) {
        return luaL_error(L, "Invalid argument size(%d) or offset(%d)", size, offset);
    }

    if ((r = ngx_http_lua_get_req(L)) == NULL) {
        return luaL_error(L, "no request found");
    }

    if ((task = ngx_http_lua_lfs_create_task(r->pool, TASK_READ)) == NULL) {
        return luaL_error(L, "can't create task");
    }
    task_ctx = task->ctx;

    if ((task_ctx->filename = ngx_palloc(r->pool, str.len + 1)) == NULL) {
        return luaL_error(L, "failed to allocate memory");
    }
    ngx_cpystrn(task_ctx->filename, str.data, str.len + 1);

    if ((task_ctx->buff = ngx_palloc(r->pool, size)) == NULL) {
        return luaL_error(L, "failed to allocate memory");
    }

    task_ctx->L = L;
    task_ctx->r = r;
    task_ctx->size = size;
    task_ctx->offset = offset;

    if (ngx_http_lua_lfs_post_task(task) != 0) {
        return luaL_error(L, "post task error.");
    }
    return lua_yield(L, 0);
}

static int ngx_http_lua_ngx_lfs_write(lua_State *L)
{
    return 0;
}

static int ngx_http_lua_ngx_lfs_copy(lua_State *L)
{
    return 0;
}

static int ngx_http_lua_ngx_lfs_unlink(lua_State *L)
{
    return 0;
}

static int ngx_http_lua_ngx_lfs_truncate(lua_State *L)
{
    return 0;
}

static int ngx_http_lua_ngx_lfs_status(lua_State *L)
{
    return 0;
}

void ngx_http_lua_inject_lfs_api(lua_State *L)
{
    lua_createtable(L, 0 /* narr */, 6 /* nrec */);    /* ngx.lfs. */

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_read);
    lua_setfield(L, -2, "read");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_write);
    lua_setfield(L, -2, "write");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_copy);
    lua_setfield(L, -2, "copy");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_unlink);
    lua_setfield(L, -2, "unlink");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_truncate);
    lua_setfield(L, -2, "truncate");

    lua_pushcfunction(L, ngx_http_lua_ngx_lfs_status);
    lua_setfield(L, -2, "status");

    lua_setfield(L, -2, "lfs");
}

#endif

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
