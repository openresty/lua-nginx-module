/*
 * Copyright (C) 2014-2015 Daurnimator
 */

/* need to include DDEBUG so that ngx_http_lua_util.h works */
#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_connection.h"

#include <math.h> /* HUGE_VAL */
#include <poll.h> /* POLLIN, POLLOUT */

#include <lua.h>
#include <lauxlib.h>

#include "ngx_core.h"
#include "ngx_alloc.h" /* ngx_alloc, ngx_free */
#include "ngx_http.h" /* ngx_http_request_t, ngx_http_run_posted_requests */
#include "ngx_http_lua_common.h" /* ngx_http_lua_module, ngx_http_lua_co_ctx_t */

#include "ngx_http_lua_util.h" /* ngx_http_lua_get_lua_vm, ngx_http_lua_run_thread, ngx_http_lua_finalize_request */
#include "ngx_http_lua_contentby.h" /* ngx_http_lua_content_wev_handler */


typedef struct {
    ngx_http_request_t    *request;
    ngx_http_lua_co_ctx_t *co_ctx;
    ngx_connection_t      *conn;
} ngx_http_lua_udata_t;


static ngx_int_t
ngx_http_lua_fd_resume_request(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t *ctx;
    lua_State          *vm;
    ngx_int_t           rc;
    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return NGX_ERROR;
    }
    /* restore normal resume handler */
    ctx->resume_handler = ngx_http_lua_wev_handler;
    /* resume lua thread */
    vm = ngx_http_lua_get_lua_vm(r, ctx);
    lua_pushboolean(ctx->cur_co_ctx->co, 1);
    /* resume coroutine */
    rc = ngx_http_lua_run_thread(vm, r, ctx, 1 /*nret*/);
    switch (rc) {
        case NGX_DONE: /* coroutine finished */
            ngx_http_lua_finalize_request(r, NGX_DONE);
            /* fall-through */
        case NGX_AGAIN: /* coroutine yielded */
            return ngx_http_lua_run_posted_threads(r->connection, vm, r, ctx);
        default: /* NGX_ERROR: coroutine failed */
            if (ctx->entered_content_phase) {
                ngx_http_lua_finalize_request(r, rc);
                return NGX_DONE;
            }
            return rc;
    }
}


static void ngx_http_lua_fd_rev_handler(ngx_event_t *ev) {
    ngx_connection_t      *conn;
    ngx_http_lua_udata_t  *u;
    ngx_http_request_t    *r;
    ngx_http_lua_co_ctx_t *co_ctx;
    ngx_http_lua_ctx_t    *ctx;

    conn = ev->data;
    u = conn->data;
    r = u->request;
    co_ctx = u->co_ctx;

    ngx_http_lua_cleanup_pending_operation(co_ctx);
    ev = NULL, u = NULL; /* now invalidated */

    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) != NULL) {
        /* set current coroutine to the one that had the event */
        ctx->cur_co_ctx = co_ctx;
        ctx->resume_handler = ngx_http_lua_fd_resume_request;
        /* queue/fire off handler */
        r->write_event_handler(r);
    }
}


static void
ngx_http_lua_fd_cleanup(ngx_http_lua_co_ctx_t *co_ctx)
{
    ngx_http_lua_udata_t *u = co_ctx->data;
    if (u->conn->data) {
        /* remove from mainloop; do not pass CLOSE_SOCKET flag */
        ngx_del_conn(u->conn, 0);
        u->conn->data = NULL;
    }
    ngx_free(u);
    co_ctx->data = NULL;
}


int
ngx_http_lua_connection_init(ngx_connection_t **p, ngx_socket_t fd, const char **err)
{
    ngx_connection_t *conn;
    if ((conn = ngx_get_connection(fd, ngx_cycle->log)) == NULL) {
        *err = "unable to get nginx connection";
        return NGX_ERROR;
    }
    conn->data = NULL;
    conn->read->handler = ngx_http_lua_fd_rev_handler;
    conn->read->log = conn->log;
    conn->write->handler = ngx_http_lua_fd_rev_handler;
    conn->write->log = conn->log;
    conn->number = ngx_atomic_fetch_add(ngx_connection_counter, 1);
    *p = conn;
    return NGX_OK;
}


void
ngx_http_lua_connection_release(ngx_connection_t *conn)
{
    /* can't use ngx_close_connection here,
       as it closes the file descriptor unconditionally */

    /* cancel timeout timer */
    if (conn->read->timer_set) {
        ngx_del_timer(conn->read);
    }

    if (conn->data) {
        /* remove from mainloop; do not pass CLOSE_SOCKET flag */
        ngx_del_conn(conn, 0);
    }

    /* delete any pending but not handled events */
#if defined(nginx_version) && nginx_version >= 1007005
    if (conn->read->posted) {
        ngx_delete_posted_event(conn->read);
    }
    if (conn->write->posted) {
        ngx_delete_posted_event(conn->write);
    }
#else
    if (conn->read->prev) {
        ngx_delete_posted_event(conn->read);
    }
    if (conn->write->prev) {
        ngx_delete_posted_event(conn->write);
    }
#endif

    /* mark as non-reusable */
    ngx_reusable_connection(conn, 0);

    /* invalidate connection object */
    conn->fd = -1;
    conn->data = NULL;
    ngx_free_connection(conn);
}


int
ngx_http_lua_connection_prep(ngx_http_request_t *r, ngx_connection_t *conn,
    int poll_mask, ngx_msec_t wait_ms, const char **err)
{
    ngx_http_lua_ctx_t    *ctx;
    ngx_http_lua_co_ctx_t *co_ctx;
    ngx_http_lua_udata_t  *u;
    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        *err ="no request ctx found";
        return NGX_ERROR;
    }
    if ((co_ctx = ctx->cur_co_ctx) == NULL) {
        *err ="no co ctx found";
        return NGX_ERROR;
    }
    if ((u = ngx_alloc(sizeof(*u), r->connection->log)) == NULL) {
        *err ="no memory";
        return NGX_ERROR;
    }
    /* cleanup old events before adding new ones */
    ngx_http_lua_cleanup_pending_operation(co_ctx);
    if ((poll_mask & POLLIN) && ngx_add_event(conn->read, NGX_READ_EVENT, NGX_LEVEL_EVENT) != NGX_OK) {
        ngx_free(u);
        *err ="unable to add to nginx main loop";
        return NGX_ERROR;
    }
    if ((poll_mask & POLLOUT) && ngx_add_event(conn->write, NGX_WRITE_EVENT, NGX_LEVEL_EVENT) != NGX_OK) {
        if (poll_mask & POLLIN) {
            ngx_del_event(conn->read, NGX_READ_EVENT, 0);
        }
        ngx_free(u);
        *err ="unable to add to nginx main loop";
        return NGX_ERROR;
    }
    conn->data = u;
    u->request = r;
    u->co_ctx = co_ctx;
    u->conn = conn;
    co_ctx->cleanup = (ngx_http_cleanup_pt)&ngx_http_lua_fd_cleanup;
    co_ctx->data = u;

    if (wait_ms != (ngx_msec_t)-1) {
        ngx_add_timer(conn->read, wait_ms);
    }

    /* make sure nginx knows what to do next */
    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    return NGX_OK;
}


/* Lua C API bindings */

static int
ngx_http_lua_connection_new(lua_State *L)
{
    ngx_connection_t **pconn;
    ngx_socket_t       fd = luaL_checkinteger(L, 1);
    const char        *errmsg;
    luaL_argcheck(L, fd >= 0, 1, "invalid file descriptor");
    pconn = lua_newuserdata(L, sizeof(*pconn));
    *pconn = NULL;
    luaL_getmetatable(L, NGX_HTTP_LUA_CONNECTION_KEY);
    lua_setmetatable(L, -2);
    if (NGX_ERROR == ngx_http_lua_connection_init(pconn, fd, &errmsg)) {
        return luaL_error(L, errmsg);
    }
    (*pconn)->data = NULL;
    return 1;
}


static ngx_connection_t*
ngx_http_lua_connection_check(lua_State *L, int idx)
{
    ngx_connection_t **pconn = luaL_checkudata(L, idx, NGX_HTTP_LUA_CONNECTION_KEY);
    luaL_argcheck(L, *pconn != NULL, idx, "ngx_connection_t has been freed");
    return *pconn;
}


static int
ngx_http_lua_connection_gc(lua_State *L)
{
    ngx_connection_t **pconn = luaL_checkudata(L, 1, NGX_HTTP_LUA_CONNECTION_KEY);
    if (NULL != *pconn) {
        ngx_http_lua_connection_release(*pconn);
        *pconn = NULL;
    }
    return 0;
}


static int
ngx_http_lua_connection_tostring(lua_State *L)
{
    ngx_connection_t *conn = ngx_http_lua_connection_check(L, 1);
    lua_pushfstring(L, "ngx_connection*: %p", conn);
    return 1;
}


static int
ngx_http_lua_connection_wait(lua_State *L)
{
    ngx_connection_t   *conn = ngx_http_lua_connection_check(L, 1);
    int                 poll_mask;
    double              timeout;
    const char         *events, *err;
    ngx_http_request_t *r;

    switch(lua_type(L, 2)) {
    case LUA_TSTRING:
        events = lua_tostring(L, 2);
        poll_mask = 0;
        while (*events) {
            if (*events == 'r') {
                poll_mask |= POLLIN;
            } else if (*events == 'w') {
                poll_mask |= POLLOUT;
            }
            events++;
        }
        break;
    case LUA_TNUMBER:
        poll_mask = lua_tointeger(L, 2);
        if (!(poll_mask & ~(POLLIN|POLLOUT))) {
            break;
        }
        /* fall through on invalid poll_mask */
    default:
        return luaL_argerror(L, 2, "expected bitwise 'or' of POLLIN|POLLOUT or characters from set 'rw'");
    }

    timeout = luaL_optnumber(L, 3, HUGE_VAL); /* default to infinite timeout */
    if (!poll_mask && timeout == HUGE_VAL) {
        return luaL_error(L, "must provide a valid events mask or finite timeout");
    }
    if ((r = ngx_http_lua_get_req(L)) == NULL) {
        return luaL_error(L, "no request found");
    }

    if (NGX_ERROR == ngx_http_lua_connection_prep(r, conn, poll_mask,
        (timeout < 0)? 0 : (timeout == HUGE_VAL)? ((ngx_msec_t)-1) : timeout*1000, &err)) {
        return luaL_error(L, err);
    }

    return lua_yield(L, 0);
}


void
ngx_http_lua_inject_connection(lua_State *L)
{
    luaL_newmetatable(L, NGX_HTTP_LUA_CONNECTION_KEY);
    lua_pushcfunction(L, ngx_http_lua_connection_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, ngx_http_lua_connection_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_newtable(L);
    lua_pushcfunction(L, ngx_http_lua_connection_wait);
    lua_setfield(L, -2, "wait");
    lua_pushcfunction(L, ngx_http_lua_connection_gc);
    lua_setfield(L, -2, "free");
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    lua_newtable(L);
    lua_pushcfunction(L, ngx_http_lua_connection_new);
    lua_setfield(L, -2, "new");
    lua_pushcfunction(L, ngx_http_lua_connection_wait);
    lua_setfield(L, -2, "wait");
    lua_pushcfunction(L, ngx_http_lua_connection_gc);
    lua_setfield(L, -2, "free");
    lua_pushinteger(L, POLLIN);
    lua_setfield(L, -2, "POLLIN");
    lua_pushinteger(L, POLLOUT);
    lua_setfield(L, -2, "POLLOUT");

    lua_setfield(L, -2, "connection");
}
