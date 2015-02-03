/*
 * Copyright (C) 2014-2015 Daurnimator
 */

/* need to include DDEBUG so that ngx_http_lua_util.h works */
#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_fd.h"

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
    rc = ngx_http_lua_run_thread(vm, r, ctx, 0 /*nret*/);
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
    ngx_http_lua_udata_t  *u;
    ngx_http_request_t    *r;
    ngx_http_lua_co_ctx_t *co_ctx;
    ngx_http_lua_ctx_t    *ctx;

    u = ((ngx_connection_t*)(ev->data))->data;
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

    ngx_http_run_posted_requests(r->connection);
}


static void
ngx_http_lua_fd_cleanup(ngx_http_lua_co_ctx_t *co_ctx)
{
    ngx_http_lua_udata_t *u = co_ctx->data;
    if (u->conn != NULL) {
        /* can't use ngx_close_connection here,
           as it closes the file descriptor unconditionally */

        /* cancel timeout timer */
        if (u->conn->read->timer_set) {
            ngx_del_timer(u->conn->read);
        }

        if (u->conn->fd != -1) {
            /* remove from mainloop; do not pass CLOSE_SOCKET flag */
            ngx_del_conn(u->conn, 0);
        }

        /* delete any pending but not handled events */
#if defined(nginx_version) && nginx_version >= 1007005
        if (u->conn->read->posted) {
            ngx_delete_posted_event(u->conn->read);
        }
        if (u->conn->write->posted) {
            ngx_delete_posted_event(u->conn->write);
        }
#else
        if (u->conn->read->prev) {
            ngx_delete_posted_event(u->conn->read);
        }
        if (u->conn->write->prev) {
            ngx_delete_posted_event(u->conn->write);
        }
#endif
        /* not sure what this line does, the 0 means non-reusable */
        ngx_reusable_connection(u->conn, 0);

        /* invalidate connection object */
        u->conn->fd = -1;
        ngx_free_connection(u->conn);

        u->conn = NULL;
    }
    ngx_free(u);
    co_ctx->data = NULL;
}


static int
ngx_http_lua_fd_wait(lua_State *L)
{
    ngx_http_request_t    *r;
    ngx_http_lua_ctx_t    *ctx;
    ngx_http_lua_co_ctx_t *co_ctx;
    ngx_http_lua_udata_t  *u;

    ngx_socket_t fd = luaL_optint(L, 1, -1); /* -1 is invalid fd */
    const char *events = luaL_optstring(L, 2, "");
    int poll_mask = 0;
    double timeout = luaL_optnumber(L, 3, HUGE_VAL); /* default to infinite timeout */
    while (*events) {
        if (*events == 'r')
            poll_mask |= POLLIN;
        else if (*events == 'w')
            poll_mask |= POLLOUT;
        events++;
    }
    if ((fd < 0 || !poll_mask) && timeout == HUGE_VAL) {
        return luaL_error(L, "must provide a valid file descriptor or timeout");
    }
    if ((r = ngx_http_lua_get_req(L)) == NULL) {
        return luaL_error(L, "no request found");
    }
    if ((ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module)) == NULL) {
        return luaL_error(L, "no request ctx found");
    }
    if ((co_ctx = ctx->cur_co_ctx) == NULL) {
        return luaL_error(L, "no co ctx found");
    }
    if ((u = ngx_alloc(sizeof(ngx_http_lua_udata_t), r->connection->log)) == NULL) {
        return luaL_error(L, "no mem");
    }
    /* always create a connection object (even if fd is < 0) */
    if ((u->conn = ngx_get_connection(fd, r->connection->log)) == NULL) {
        ngx_free(u);
        return luaL_error(L, "unable to get nginx connection");
    }
    ngx_http_lua_cleanup_pending_operation(co_ctx);

    u->conn->data = u;
    u->conn->read->handler = ngx_http_lua_fd_rev_handler;
    u->conn->read->log = u->conn->log;
    u->conn->write->handler = ngx_http_lua_fd_rev_handler;
    u->conn->write->log = u->conn->log;
    u->conn->number = ngx_atomic_fetch_add(ngx_connection_counter, 1);

    if (fd >= 0) {
        if ((poll_mask & POLLIN) && ngx_handle_read_event(u->conn->read, NGX_LEVEL_EVENT) != NGX_OK) {
            ngx_free_connection(u->conn);
            ngx_free(u);
            return luaL_error(L, "unable to add to nginx main loop");
        }
        if ((poll_mask & POLLOUT) && ngx_handle_write_event(u->conn->write, NGX_LEVEL_EVENT) != NGX_OK) {
            if (poll_mask & POLLIN) ngx_del_event(u->conn->read, NGX_READ_EVENT, 0);
            ngx_free_connection(u->conn);
            ngx_free(u);
            return luaL_error(L, "unable to add to nginx main loop");
        }
    }

    u->request = r;

    u->co_ctx = co_ctx;
    co_ctx->cleanup = (ngx_http_cleanup_pt)&ngx_http_lua_fd_cleanup;
    co_ctx->data = u;

    if (timeout != HUGE_VAL) { /* no point adding an infinite timeout */
        ngx_add_timer(u->conn->read, (ngx_msec_t)(timeout * 1000));
    }

    /* make sure nginx knows what to do next */
    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }

    return lua_yield(L, 0);
}


void
ngx_http_lua_inject_fd(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_fd_wait);
    lua_setfield(L, -2, "wait");
}
