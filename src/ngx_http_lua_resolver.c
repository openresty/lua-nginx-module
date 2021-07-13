
#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_util.h"
#include "ngx_http_lua_contentby.h"


typedef struct ngx_http_lua_resolver_ctx_s {
    ngx_http_request_t              *request;
    u_char                          *buf;
    size_t                          *buf_size;
    ngx_http_lua_co_ctx_t           *curr_co_ctx;
    ngx_resolver_ctx_t              *resolver_ctx;
    ngx_int_t                        exit_code;
    unsigned                         ipv4:1;
    unsigned                         ipv6:1;
} ngx_http_lua_resolver_ctx_t;


static void ngx_http_lua_resolve_handler(ngx_resolver_ctx_t *rctx);
static void ngx_http_lua_resolve_cleanup(void *data);
static void ngx_http_lua_resolve_empty_handler(ngx_resolver_ctx_t *ctx);
static ngx_int_t ngx_http_lua_resolve_resume(ngx_http_request_t *r);
static int ngx_http_lua_resolve_retval(ngx_http_lua_resolver_ctx_t *ctx,
                                       lua_State *L);


int
ngx_http_lua_ffi_resolve(ngx_http_lua_resolver_ctx_t *ctx, u_char *hostname)
{
    u_char                    *buf;
    size_t                    *buf_size;
    lua_State                 *L;
    ngx_str_t                  host;
    ngx_http_lua_ctx_t        *lctx;
    ngx_http_request_t        *r;
    ngx_resolver_ctx_t        *rctx;
    ngx_http_lua_co_ctx_t     *coctx;
    ngx_http_core_loc_conf_t  *clcf;

#if (NGX_HAVE_INET6)
    struct in6_addr  inaddr6;
#endif

    buf = ctx->buf;
    buf_size = ctx->buf_size;

    r = ctx->request;
    if (r == NULL) {
        *ctx->buf_size = ngx_snprintf(buf, *buf_size, "no request") - buf;
        return NGX_ERROR;
    }

    lctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (lctx == NULL) {
        *buf_size = ngx_snprintf(buf, *buf_size, "no lua ctx") - buf;
        return NGX_ERROR;
    }

    L = ngx_http_lua_get_lua_vm(r, lctx);

    ngx_http_lua_check_context(L, lctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                                       | NGX_HTTP_LUA_CONTEXT_ACCESS
                                       | NGX_HTTP_LUA_CONTEXT_CONTENT
                                       | NGX_HTTP_LUA_CONTEXT_TIMER
                                       | NGX_HTTP_LUA_CONTEXT_SSL_CERT
                                       | NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH);

    host.data = hostname;
    host.len = ngx_strlen(hostname);

    if (ngx_inet_addr(host.data, host.len) != INADDR_NONE
#if (NGX_HAVE_INET6)
        || ngx_inet6_addr(host.data, host.len, inaddr6.s6_addr) == NGX_OK
#endif
        )
    {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "given hostname contains a network address");

        *buf_size = ngx_cpystrn(buf, host.data, host.len + 1) - buf;
        return NGX_OK;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    rctx = ngx_resolve_start(clcf->resolver, NULL);
    if (rctx == NULL) {
        *buf_size = ngx_snprintf(buf, *buf_size, "failed to start the resolver")
                    - buf;
        return NGX_ERROR;
    }

    if (rctx == NGX_NO_RESOLVER) {
        *buf_size = ngx_snprintf(buf, *buf_size, "no resolver defined "
                                 "to resolve \"%s\"", host.data)
                    - buf;
        return NGX_ERROR;
    }

    rctx->name = host;
    rctx->handler = ngx_http_lua_resolve_handler;
    rctx->data = ctx;
    rctx->timeout = clcf->resolver_timeout;

    ctx->resolver_ctx = rctx;
    ctx->curr_co_ctx = lctx->cur_co_ctx;
    coctx = lctx->cur_co_ctx;
    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_resolve_cleanup;
    coctx->data = ctx;

    if (ngx_resolve_name(rctx) != NGX_OK) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua resolver fail to run resolver immediately");

        coctx->cleanup = NULL;
        coctx->data = NULL;
        ctx->resolver_ctx = NULL;

        *buf_size = ngx_snprintf(buf, *buf_size, "%s could not be resolved",
                                 host.data)
                    - buf;
        return NGX_ERROR;
    }

    if (rctx->async) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "resolution is going to be performed asynchronously");
        return NGX_DONE;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "resolution was finished with code %d", ctx->exit_code);

    return ctx->exit_code;
}


static void
ngx_http_lua_resolve_handler(ngx_resolver_ctx_t *rctx)
{
    u_char                       *buf;
    size_t                       *buf_size;
    unsigned                      async;
    ngx_uint_t                    i;
    ngx_connection_t             *c;
    ngx_http_request_t           *r;
    ngx_http_lua_ctx_t           *lctx;
    ngx_resolver_addr_t          *addr;
    ngx_http_lua_resolver_ctx_t  *ctx;

    ctx = rctx->data;
    buf = ctx->buf;
    buf_size = ctx->buf_size;
    r = ctx->request;
    c = r->connection;
    async = rctx->async;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0, "lua ngx resolve handler");

    lctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (lctx == NULL) {
        return;
    }

    lctx->cur_co_ctx = ctx->curr_co_ctx;
    ctx->curr_co_ctx->cleanup = NULL;

    if (rctx->state) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0, "resolve error: %s "
                       "(async:%d)", ngx_resolver_strerror(rctx->state), async);

        *buf_size = ngx_snprintf(buf, *buf_size, "%s could not be resolved "
                                 "(%d: %s)", rctx->name.data, (int) rctx->state,
                                 ngx_resolver_strerror(rctx->state))
                    - buf;

        goto failed;
    }

#if (NGX_DEBUG)
    {
        u_char     text[NGX_SOCKADDR_STRLEN];
        ngx_str_t  tmp;

        tmp.data = text;

        for (i = 0; i < rctx->naddrs; i++) {
            tmp.len = ngx_sock_ntop(rctx->addrs[i].sockaddr,
                                    rctx->addrs[i].socklen,
                                    text, NGX_SOCKADDR_STRLEN, 0);

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "name was resolved to %V", &tmp);
        }
    }
#endif

    /* NG: On a cache hit, Nginx resolver performs random rotation of
     * addrs list on every invocation, so, here we just looking for
     * the first one that satisfies the requirements.
     * See ngx_resolve_name_locked()/ngx_resolver_export() for details */
    for (i = 0; i < rctx->naddrs; i++) {
        addr = &rctx->addrs[i];
        if ((addr->sockaddr->sa_family == AF_INET && ctx->ipv4)
#if (NGX_HAVE_INET6)
            || (addr->sockaddr->sa_family == AF_INET6 && ctx->ipv6)
#endif
            )
        {
            *buf_size = ngx_sock_ntop(addr->sockaddr, addr->socklen, ctx->buf,
                                      *buf_size, 0);

            goto done;
        }
    }

    *buf_size = ngx_snprintf(buf, *buf_size, "no suitable address found for "
                             "%s out of %d received", rctx->name.data,
                             rctx->naddrs)
                - buf;

failed:

    ctx->exit_code = NGX_ERROR;

done:

    ngx_resolve_name_done(rctx);
    ctx->resolver_ctx = NULL;
    ctx->curr_co_ctx = NULL;

    if (async) {
        if (lctx->entered_content_phase) {
            (void) ngx_http_lua_resolve_resume(r);

        } else {
            lctx->resume_handler = ngx_http_lua_resolve_resume;
            ngx_http_core_run_phases(r);
        }

        ngx_http_run_posted_requests(c);
    }
}


static ngx_int_t
ngx_http_lua_resolve_resume(ngx_http_request_t *r)
{
    int                           nret;
    lua_State                    *vm;
    ngx_int_t                     rc;
    ngx_uint_t                    nreqs;
    ngx_connection_t             *c;
    ngx_http_lua_ctx_t           *lctx;
    ngx_http_lua_co_ctx_t        *coctx;
    ngx_http_lua_resolver_ctx_t  *ctx;

    lctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (lctx == NULL) {
        return NGX_ERROR;
    }

    lctx->resume_handler = ngx_http_lua_wev_handler;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua resolve operation is done, resuming lua thread");

    coctx = lctx->cur_co_ctx;

    dd("coctx: %p", coctx);

    ctx = coctx->data;

    nret = ngx_http_lua_resolve_retval(ctx, lctx->cur_co_ctx->co);

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, lctx);
    nreqs = c->requests;

    rc = ngx_http_lua_run_thread(vm, r, lctx, nret);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, lctx, nreqs);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, lctx, nreqs);
    }

    if (lctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


static void
ngx_http_lua_resolve_cleanup(void *data)
{
    ngx_resolver_ctx_t            *rctx;
    ngx_http_lua_co_ctx_t         *coctx;
    ngx_http_lua_resolver_ctx_t   *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua ngx.resolve abort resolver");

    coctx = data;
    ctx = coctx->data;
    rctx = ctx->resolver_ctx;

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
ngx_http_lua_resolve_retval(ngx_http_lua_resolver_ctx_t *ctx, lua_State *L)
{
    if (ctx->exit_code == NGX_OK) {
        lua_pushlstring(L, (const char *) ctx->buf, *ctx->buf_size);

        return 1;
    }

    lua_pushnil(L);
    lua_pushlstring(L, (const char *) ctx->buf, *ctx->buf_size);

    return 2;
}

void
ngx_http_lua_ffi_resolver_destroy(ngx_http_lua_resolver_ctx_t *ctx)
{
    if (ctx->resolver_ctx == NULL) {
        return;
    }

    ngx_resolve_name_done(ctx->resolver_ctx);
    ctx->resolver_ctx = NULL;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
