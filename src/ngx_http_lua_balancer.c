
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_balancer.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_directive.h"


struct ngx_http_lua_balancer_peer_data_s {
    /* the round robin data must be first */
    ngx_http_upstream_rr_peer_data_t    rrp;

    ngx_http_lua_srv_conf_t            *conf;
    ngx_http_request_t                 *request;

    ngx_event_get_peer_pt               get_rr_peer;

    ngx_uint_t                          more_tries;
    ngx_uint_t                          total_tries;

    struct sockaddr                    *sockaddr;
    socklen_t                           socklen;

    ngx_str_t                           host;
    in_port_t                           port;

    int                                 last_peer_state;
};


static ngx_int_t ngx_http_lua_balancer_init(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_lua_balancer_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_lua_balancer_get_peer(ngx_peer_connection_t *pc,
    void *data);
static ngx_int_t ngx_http_lua_balancer_by_chunk(lua_State *L,
    ngx_http_request_t *r);
void ngx_http_lua_balancer_free_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state);


ngx_int_t
ngx_http_lua_balancer_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadfile(r->connection->log, L,
                                     lscf->balancer.src.data,
                                     lscf->balancer.src_key);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_balancer_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_balancer_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadbuffer(r->connection->log, L,
                                       lscf->balancer.src.data,
                                       lscf->balancer.src.len,
                                       lscf->balancer.src_key,
                                       "=balancer_by_lua");
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_balancer_by_chunk(L, r);
}


char *
ngx_http_lua_balancer_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_balancer_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_balancer_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                      *p;
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_srv_conf_t     *lscf = conf;

    ngx_http_upstream_srv_conf_t      *uscf;

    dd("enter");

    /*  must specifiy a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lscf->balancer.handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    lscf->balancer.handler = (ngx_http_lua_srv_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_balancer_handler_file) {
        /* Lua code in an external file */

        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->balancer.src.data = name;
        lscf->balancer.src.len = ngx_strlen(name);

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->balancer.src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

    } else {
        /* inlined Lua code */

        lscf->balancer.src = value[1];

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->balancer.src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';
    }

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    if (uscf->peer.init_upstream) {
        ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                           "load balancing method redefined");
    }

    uscf->peer.init_upstream = ngx_http_lua_balancer_init;

    uscf->flags = NGX_HTTP_UPSTREAM_CREATE
                  |NGX_HTTP_UPSTREAM_WEIGHT
                  |NGX_HTTP_UPSTREAM_MAX_FAILS
                  |NGX_HTTP_UPSTREAM_FAIL_TIMEOUT
                  |NGX_HTTP_UPSTREAM_DOWN;

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_lua_balancer_init(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us)
{
    if (ngx_http_upstream_init_round_robin(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    /* this callback is called upon individual requests */
    us->peer.init = ngx_http_lua_balancer_init_peer;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_balancer_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_lua_srv_conf_t            *bcf;
    ngx_http_lua_balancer_peer_data_t  *bp;

    bp = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_balancer_peer_data_t));
    if (bp == NULL) {
        return NGX_ERROR;
    }

    r->upstream->peer.data = &bp->rrp;

    if (ngx_http_upstream_init_round_robin_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    r->upstream->peer.get = ngx_http_lua_balancer_get_peer;
    r->upstream->peer.free = ngx_http_lua_balancer_free_peer;

    bcf = ngx_http_conf_upstream_srv_conf(us, ngx_http_lua_module);

    bp->conf = bcf;
    bp->get_rr_peer = ngx_http_upstream_get_round_robin_peer;
    bp->request = r;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_balancer_get_peer(ngx_peer_connection_t *pc, void *data)
{
    lua_State                          *L;
    ngx_int_t                           rc;
    ngx_http_request_t                 *r;
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_lua_srv_conf_t            *lscf;
    ngx_http_lua_main_conf_t           *lmcf;
    ngx_http_lua_balancer_peer_data_t  *bp = data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "lua balancer peer, try: %ui", pc->tries);

    lscf = bp->conf;

    r = bp->request;

    ngx_http_lua_assert(lscf->balancer.handler && r);

    L = ngx_http_lua_get_lua_vm(r, NULL);

    bp->sockaddr = NULL;
    bp->socklen = 0;
    bp->more_tries = 0;
    bp->total_tries++;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    /* balancer_by_lua does not support yielding and
     * there cannot be any conflicts among concurrent requests,
     * thus it is safe to store the peer data in the main conf.
     */
    lmcf->balancer_peer_data = bp;

    rc = lscf->balancer.handler(r, lscf, L);

    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx->exited && ctx->exit_code != NGX_OK) {
        rc = ctx->exit_code;
        if (rc == NGX_ERROR || rc == NGX_BUSY || rc == NGX_DECLINED) {
            return rc;
        }

        if (rc > NGX_OK) {
            return NGX_ERROR;
        }
    }

    if (bp->sockaddr && bp->socklen) {
        pc->sockaddr = bp->sockaddr;
        pc->socklen = bp->socklen;
        pc->name = &bp->host;
        bp->rrp.peers->single = 0;

        if (bp->more_tries) {
            r->upstream->peer.tries += bp->more_tries;
        }

        dd("tries: %d", (int) r->upstream->peer.tries);

        return NGX_OK;
    }

    return bp->get_rr_peer(pc, &bp->rrp);
}


static ngx_int_t
ngx_http_lua_balancer_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    u_char                  *err_msg;
    size_t                   len;
    ngx_int_t                rc;
    ngx_http_lua_ctx_t      *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

    } else {
        dd("reset ctx");
        ngx_http_lua_reset_ctx(r, L, ctx);
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_BALANCER;

    /* init nginx context in Lua VM */
    ngx_http_lua_set_req(L, r);
    ngx_http_lua_create_new_globals_table(L, 0 /* narr */, 1 /* nrec */);

    /*  {{{ make new env inheriting main thread's globals table */
    lua_createtable(L, 0, 1 /* nrec */);   /* the metatable for the new env */
    ngx_http_lua_get_globals_table(L);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
    /*  }}} */

    lua_setfenv(L, -2);    /*  set new running env for the code closure */

    lua_pushcfunction(L, ngx_http_lua_traceback);
    lua_insert(L, 1);  /* put it under chunk and args */

    /*  protected call user code */
    rc = lua_pcall(L, 0, 1, 1);

    lua_remove(L, 1);  /* remove traceback function */

    dd("rc == %d", (int) rc);

    if (rc != 0) {
        /*  error occured when running loaded code */
        err_msg = (u_char *) lua_tolstring(L, -1, &len);

        if (err_msg == NULL) {
            err_msg = (u_char *) "unknown reason";
            len = sizeof("unknown reason") - 1;
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "failed to run balancer_by_lua*: %*s", len, err_msg);

        lua_settop(L, 0); /*  clear remaining elems on stack */

        return NGX_ERROR;
    }

    lua_settop(L, 0); /*  clear remaining elems on stack */
    return rc;
}


void
ngx_http_lua_balancer_free_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_http_lua_balancer_peer_data_t  *bp = data;

    if (bp->sockaddr && bp->socklen) {
        bp->last_peer_state = (int) state;

        if (pc->tries) {
            pc->tries--;
        }

        return;
    }

    /* fallback */

    ngx_http_upstream_free_round_robin_peer(pc, data, state);
}


#ifndef NGX_LUA_NO_FFI_API

int
ngx_http_lua_ffi_balancer_set_current_peer(ngx_http_request_t *r,
    const u_char *addr, size_t addr_len, int port, char **err)
{
    ngx_url_t              url;
    ngx_http_lua_ctx_t    *ctx;
    ngx_http_upstream_t   *u;

    ngx_http_lua_main_conf_t           *lmcf;
    ngx_http_lua_balancer_peer_data_t  *bp;

    if (r == NULL) {
        *err = "no request found";
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        *err = "no upstream found";
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no ctx found";
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    /* we cannot read r->upstream->peer.data here directly because
     * it could be overridden by other modules like
     * ngx_http_upstream_keepalive_module.
     */
    bp = lmcf->balancer_peer_data;
    if (bp == NULL) {
        *err = "no upstream peer data found";
        return NGX_ERROR;
    }

    ngx_memzero(&url, sizeof(ngx_url_t));

    url.url.data = ngx_palloc(r->pool, addr_len);
    if (url.url.data == NULL) {
        *err = "no memory";
        return NGX_ERROR;
    }

    ngx_memcpy(url.url.data, addr, addr_len);

    url.url.len = addr_len;
    url.default_port = (in_port_t) port;
    url.uri_part = 0;
    url.no_resolve = 1;

    if (ngx_parse_url(r->pool, &url) != NGX_OK) {
        if (url.err) {
            *err = url.err;
        }

        return NGX_ERROR;
    }

    if (url.addrs && url.addrs[0].sockaddr) {
        bp->sockaddr = url.addrs[0].sockaddr;
        bp->socklen = url.addrs[0].socklen;
        bp->host = url.addrs[0].name;

    } else {
        *err = "no host allowed";
        return NGX_ERROR;
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_balancer_set_more_tries(ngx_http_request_t *r,
    int count, char **err)
{
    ngx_uint_t             max_tries;
    ngx_http_lua_ctx_t    *ctx;
    ngx_http_upstream_t   *u;

    ngx_http_lua_main_conf_t           *lmcf;
    ngx_http_lua_balancer_peer_data_t  *bp;

    if (r == NULL) {
        *err = "no request found";
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        *err = "no upstream found";
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no ctx found";
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    bp = lmcf->balancer_peer_data;
    if (bp == NULL) {
        *err = "no upstream peer data found";
        return NGX_ERROR;
    }

#if (nginx_version >= 1007005)
    max_tries = r->upstream->conf->next_upstream_tries;

    if (bp->total_tries + count > max_tries) {
        count = max_tries - bp->total_tries;
        *err = "reduced tries due to limit";

    } else {
        *err = NULL;
    }
#else
    *err = NULL;
#endif

    bp->more_tries = count;
    return NGX_OK;
}


int
ngx_http_lua_ffi_balancer_get_last_failure(ngx_http_request_t *r,
    int *status, char **err)
{
    ngx_http_lua_ctx_t         *ctx;
    ngx_http_upstream_t        *u;
    ngx_http_upstream_state_t  *state;

    ngx_http_lua_balancer_peer_data_t  *bp;
    ngx_http_lua_main_conf_t           *lmcf;

    if (r == NULL) {
        *err = "no request found";
        return NGX_ERROR;
    }

    u = r->upstream;

    if (u == NULL) {
        *err = "no upstream found";
        return NGX_ERROR;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *err = "no ctx found";
        return NGX_ERROR;
    }

    if ((ctx->context & NGX_HTTP_LUA_CONTEXT_BALANCER) == 0) {
        *err = "API disabled in the current context";
        return NGX_ERROR;
    }

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    bp = lmcf->balancer_peer_data;
    if (bp == NULL) {
        *err = "no upstream peer data found";
        return NGX_ERROR;
    }

    if (r->upstream_states && r->upstream_states->nelts > 1) {
        state = r->upstream_states->elts;
        *status = (int) state[r->upstream_states->nelts - 2].status;

    } else {
        *status = 0;
    }

    return bp->last_peer_state;
}

#endif  /* NGX_LUA_NO_FFI_API */
