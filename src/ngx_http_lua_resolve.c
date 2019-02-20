
/*
 * Copyright (C) Sergey Kharkhardin (slimboyfat)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_util.h"
#include "ngx_http_lua_resolve.h"
#include "ngx_http_lua_contentby.h"


typedef struct ngx_http_lua_resolve_ctx_s
        ngx_http_lua_resolve_ctx_t;


static int ngx_http_lua_ngx_resolve(lua_State *L);
static void ngx_http_lua_resolve_handler(ngx_resolver_ctx_t *ctx);
static void ngx_http_lua_resolve_cleanup(void *data);
static void ngx_http_lua_resolve_empty_handler(ngx_resolver_ctx_t *ctx);
static ngx_int_t ngx_http_lua_resolve_resume(ngx_http_request_t *r);
static int ngx_http_lua_resolve_select_retval(ngx_http_lua_resolve_ctx_t *u,
    lua_State *L);
static int ngx_http_lua_resolve_get_retval(struct sockaddr *sockaddr,
    socklen_t socklen, lua_State *L);
static int ngx_http_lua_resolve_set_query_option(const char *name,
    unsigned *option, lua_State *L);

struct ngx_http_lua_resolve_ctx_s {
    ngx_http_request_t            *request;
    ngx_http_upstream_resolved_t  *resolved;
    ngx_http_lua_co_ctx_t         *curr_co_ctx;
    unsigned                      ipv4:1;
    unsigned                      ipv6:1;
};


static int ngx_http_lua_ngx_resolve(lua_State *L)
{
    int                          n, saved_top;
    size_t                       len;
    u_char                      *p;
    ngx_int_t                    rc;
    ngx_str_t                    host;
    ngx_url_t                    url;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_request_t          *r;
    ngx_resolver_ctx_t          *rctx, temp;
    ngx_http_lua_co_ctx_t       *coctx;
    ngx_http_core_loc_conf_t    *clcf;
    ngx_http_lua_resolve_ctx_t  *u;

    unsigned  ipv4 = 1;
    unsigned  ipv6 = 0;

    n = lua_gettop(L);
    if (n != 1 && n != 2) {
        return luaL_error(L, "passed %d arguments, but accepted 1 or 2", n);
    }

    if (lua_type(L, 1) != LUA_TSTRING) {
        return luaL_error(L, "1st parameter must be a string");
    }

    if (n == 2) {
        if (lua_type(L, 2) != LUA_TTABLE) {
            return luaL_error(L, "2nd parameter must be a table");
        }

        rc = ngx_http_lua_resolve_set_query_option("ipv4", &ipv4, L);
        if (rc != NGX_OK) {
            return rc;
        }

        rc = ngx_http_lua_resolve_set_query_option("ipv6", &ipv6, L);
        if (rc != NGX_OK) {
            return rc;
        }
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                                       | NGX_HTTP_LUA_CONTEXT_ACCESS
                                       | NGX_HTTP_LUA_CONTEXT_CONTENT);

    p = (u_char *) luaL_checklstring(L, 1, &len);

    host.data = ngx_palloc(r->pool, len + 1);
    if (host.data == NULL) {
        return luaL_error(L, "no memory");
    }

    host.len = len;

    ngx_memcpy(host.data, p, len);
    host.data[len] = '\0';

    ngx_memzero(&url, sizeof(ngx_url_t));

    url.url.len = host.len;
    url.url.data = host.data;
    url.default_port = (in_port_t) 0;
    url.no_resolve = 1;

    if (ngx_parse_url(r->pool, &url) != NGX_OK) {
        lua_pushnil(L);

        if (url.err) {
            lua_pushfstring(L, "failed to parse host name \"%s\": %s",
                            host.data, url.err);

        } else {
            lua_pushfstring(L, "failed to parse host name \"%s\"", host.data);
        }

        return 2;
    }

    if (url.addrs && url.addrs[0].sockaddr) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "the given host name is address");

        return ngx_http_lua_resolve_get_retval(url.addrs[0].sockaddr,
                                               url.addrs[0].socklen, L);
    }

    u = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_resolve_ctx_t));
    if (u == NULL) {
        return luaL_error(L, "no memory");
    }

    u->ipv4 = ipv4;
    u->ipv6 = ipv6;
    u->request = r; /* set the controlling request */

    u->resolved = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_resolved_t));
    if (u->resolved == NULL) {
        return luaL_error(L, "no memory");
    }

    u->resolved->host = host;
    u->resolved->port = (in_port_t) 0;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    temp.name = host;
    rctx = ngx_resolve_start(clcf->resolver, &temp);
    if (rctx == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "failed to start the resolver");
        return 2;
    }

    if (rctx == NGX_NO_RESOLVER) {
        lua_pushnil(L);
        lua_pushfstring(L, "no resolver defined to resolve \"%s\"", host.data);
        return 2;
    }

    rctx->name = host;
    rctx->handler = ngx_http_lua_resolve_handler;
    rctx->data = u;
    rctx->timeout = clcf->resolver_timeout;

    u->resolved->ctx = rctx;
    u->curr_co_ctx = ctx->cur_co_ctx;
    coctx = ctx->cur_co_ctx;

    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_resolve_cleanup;
    coctx->data = u;

    saved_top = lua_gettop(L);

    if (ngx_resolve_name(rctx) != NGX_OK) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua ngx.resolve fail to run resolver immediately");

        coctx->cleanup = NULL;
        coctx->data = NULL;

        u->resolved->ctx = NULL;
        lua_pushnil(L);
        lua_pushfstring(L, "%s could not be resolved", host.data);

        return 2;
    }

    if (rctx->async) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "DNS resolver is going to be queried asynchronously");

        return lua_yield(L, 0);
    }

    /* Resolver's response was retrieved synchronously (from cache) */
    n = lua_gettop(L) - saved_top;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "ngx.resolve has %i result(s) cached", n);

    return n;
}


static void
ngx_http_lua_resolve_handler(ngx_resolver_ctx_t *ctx)
{
    lua_State                     *L;
    ngx_connection_t              *c;
    ngx_http_request_t            *r;
    ngx_http_lua_ctx_t            *lctx;
    ngx_http_lua_resolve_ctx_t    *u;
    ngx_http_upstream_resolved_t  *ur;

    u = ctx->data;
    r = u->request;
    c = r->connection;
    ur = u->resolved;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua ngx.resolve handler");

    lctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (lctx == NULL) {
        return;
    }

    lctx->cur_co_ctx = u->curr_co_ctx;
    u->curr_co_ctx->cleanup = NULL;
    L = lctx->cur_co_ctx->co;

    if (ctx->state) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0, "ngx.resolve error: %s "
                       "(async:%d)", ngx_resolver_strerror(ctx->state),
                       (int) ctx->async);

        lua_pushnil(L);
        lua_pushlstring(L, (char *) ctx->name.data, ctx->name.len);
        lua_pushfstring(L, " could not be resolved (%d: %s)",
            (int) ctx->state, ngx_resolver_strerror(ctx->state));
        lua_concat(L, 2);

        ngx_resolve_name_done(ctx);
        ur->ctx = NULL;
        u->curr_co_ctx = NULL;

        if (ctx->async) {
            goto resume;
        }

        return;
    }

    ur->naddrs = ctx->naddrs;
    ur->addrs = ctx->addrs;

#if (NGX_DEBUG)
    {
        u_char      text[NGX_SOCKADDR_STRLEN];
        ngx_str_t   addr;
        ngx_uint_t  i;

        addr.data = text;

        for (i = 0; i < ctx->naddrs; i++) {
            addr.len = ngx_sock_ntop(ur->addrs[i].sockaddr, ur->addrs[i].socklen,
                                     text, NGX_SOCKADDR_STRLEN, 0);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "name was resolved to %V", &addr);
        }
    }
#endif

    ngx_resolve_name_done(ctx);
    ur->ctx = NULL;
    u->curr_co_ctx = NULL;

    if (!ctx->async) {
        (void) ngx_http_lua_resolve_select_retval(u, L);

        return;
    }

resume:
    if (lctx->entered_content_phase) {
        (void) ngx_http_lua_resolve_resume(r);

    } else {
        lctx->resume_handler = ngx_http_lua_resolve_resume;
        ngx_http_core_run_phases(r);
    }

    ngx_http_run_posted_requests(c);
}


static ngx_int_t
ngx_http_lua_resolve_resume(ngx_http_request_t *r)
{
    int                          nret;
    lua_State                   *vm;
    ngx_int_t                    rc;
    ngx_uint_t                   nreqs;
    ngx_connection_t            *c;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *coctx;
    ngx_http_lua_resolve_ctx_t  *u;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua ngx.resolve operation is done, resuming lua thread");

    coctx = ctx->cur_co_ctx;

    dd("coctx: %p", coctx);

    u = coctx->data;

    nret = ngx_http_lua_resolve_select_retval(u, ctx->cur_co_ctx->co);

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);
    nreqs = c->requests;

    rc = ngx_http_lua_run_thread(vm, r, ctx, nret);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx, nreqs);
    }

    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


static void
ngx_http_lua_resolve_cleanup(void *data)
{
    ngx_resolver_ctx_t            *rctx;
    ngx_http_lua_co_ctx_t         *coctx = data;
    ngx_http_upstream_resolved_t  *resolved;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua ngx.resolve abort resolver");

    resolved = coctx->data;
    if (resolved == NULL) {
        return;
    }

    rctx = resolved->ctx;
    if (rctx == NULL) {
        return;
    }

    /* just to be safer */
    rctx->handler = ngx_http_lua_resolve_empty_handler;

    ngx_resolve_name_done(rctx);
}


static void
ngx_http_lua_resolve_empty_handler(ngx_resolver_ctx_t *ctx)
{
    /* do nothing */
}


static int
ngx_http_lua_resolve_select_retval(ngx_http_lua_resolve_ctx_t *u, lua_State *L)
{
    ngx_uint_t                     i;
    ngx_resolver_addr_t           *addr;
    ngx_http_upstream_resolved_t  *ur = u->resolved;

    for (i = 0; i < ur->naddrs; i++) {
        addr = &ur->addrs[i];
        switch (addr->sockaddr->sa_family) {
#if (NGX_HAVE_INET6)
            case AF_INET6:
                if (u->ipv6) {
                    return ngx_http_lua_resolve_get_retval(addr->sockaddr,
                                                           addr->socklen, L);
                }
                break;
#endif
            default: /* AF_INET */
                if (u->ipv4) {
                    return ngx_http_lua_resolve_get_retval(addr->sockaddr,
                                                           addr->socklen, L);
                }
        }
    }

    lua_pushnil(L);
    lua_pushliteral(L, "address not found");

    return 2;
}


static int
ngx_http_lua_resolve_get_retval(struct sockaddr *sockaddr, socklen_t socklen,
    lua_State *L)
{
    size_t  len;
    u_char  text[NGX_SOCKADDR_STRLEN];

    len = ngx_sock_ntop(sockaddr, socklen, text, NGX_SOCKADDR_STRLEN, 0);
    lua_pushlstring(L, (const char *) text, len);

    return 1;
}


static int
ngx_http_lua_resolve_set_query_option(const char *name, unsigned *option, lua_State *L)
{
    lua_getfield(L, 2, name);

    switch (lua_type(L, -1)) {
        case LUA_TNIL:
            /* do nothing */
            break;

        case LUA_TBOOLEAN:
            *option = lua_toboolean(L, -1);
            break;

        default:
            return luaL_error(L, "bad \"%s\" option value type: %s",
                       name, luaL_typename(L, -1));
    }

    lua_pop(L, 1);

    return NGX_OK;
}


void
ngx_http_lua_inject_resolve_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_resolve);
    lua_setfield(L, -2, "resolve");
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
