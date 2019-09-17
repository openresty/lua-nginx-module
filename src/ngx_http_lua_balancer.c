
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


typedef struct {
    ngx_uint_t                               size;
    ngx_uint_t                               connections;

    uint32_t                                 crc32;

    lua_State                               *lua_vm;

    ngx_queue_t                              cache;
    ngx_queue_t                              free;
} ngx_http_lua_balancer_keepalive_pool_t;


typedef struct {
    ngx_queue_t                              queue;
    ngx_connection_t                        *connection;

    ngx_http_lua_balancer_keepalive_pool_t  *cpool;
} ngx_http_lua_balancer_keepalive_item_t;


struct ngx_http_lua_balancer_peer_data_s {
    ngx_uint_t                              cpool_size;
    ngx_uint_t                              keepalive_requests;
    ngx_msec_t                              keepalive_timeout;

    ngx_uint_t                              more_tries;
    ngx_uint_t                              total_tries;

    int                                     last_peer_state;

    uint32_t                                cpool_crc32;

    void                                   *data;

    ngx_event_get_peer_pt                   original_get_peer;
    ngx_event_free_peer_pt                  original_free_peer;

#if (NGX_HTTP_SSL)
    ngx_event_set_peer_session_pt           original_set_session;
    ngx_event_save_peer_session_pt          original_save_session;
#endif

    ngx_http_request_t                     *request;
    ngx_http_lua_srv_conf_t                *conf;
    ngx_http_lua_balancer_keepalive_pool_t *cpool;

    ngx_str_t                              *host;

    struct sockaddr                        *sockaddr;
    socklen_t                               socklen;

    unsigned                                keepalive:1;

#if !(HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
    unsigned                                cloned_upstream_conf:1;
#endif
};


static ngx_int_t ngx_http_lua_balancer_by_chunk(lua_State *L,
    ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_balancer_init(ngx_conf_t *cf,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_lua_balancer_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us);
static ngx_int_t ngx_http_lua_balancer_get_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_lua_balancer_free_peer(ngx_peer_connection_t *pc,
    void *data, ngx_uint_t state);
static ngx_int_t ngx_http_lua_balancer_create_keepalive_pool(lua_State *L,
    ngx_log_t *log, uint32_t cpool_crc32, ngx_uint_t cpool_size,
    ngx_http_lua_balancer_keepalive_pool_t **cpool);
static void ngx_http_lua_balancer_get_keepalive_pool(lua_State *L,
    uint32_t cpool_crc32, ngx_http_lua_balancer_keepalive_pool_t **cpool);
static void ngx_http_lua_balancer_free_keepalive_pool(ngx_log_t *log,
    ngx_http_lua_balancer_keepalive_pool_t *cpool);
static void ngx_http_lua_balancer_close(ngx_connection_t *c);
static void ngx_http_lua_balancer_dummy_handler(ngx_event_t *ev);
static void ngx_http_lua_balancer_close_handler(ngx_event_t *ev);
#if (NGX_HTTP_SSL)
static ngx_int_t ngx_http_lua_balancer_set_session(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_lua_balancer_save_session(ngx_peer_connection_t *pc,
    void *data);
#endif


#define ngx_http_lua_balancer_keepalive_is_enabled(bp)                       \
    (bp->keepalive)

#define ngx_http_lua_balancer_peer_set(bp)                                   \
    (bp->sockaddr && bp->socklen)


static char              ngx_http_lua_balancer_keepalive_pools_table_key;
static struct sockaddr  *ngx_http_lua_balancer_default_server_sockaddr;


ngx_int_t
ngx_http_lua_balancer_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadfile(r->connection->log, L,
                                     lscf->balancer.src.data,
                                     &lscf->balancer.src_ref,
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
                                       &lscf->balancer.src_ref,
                                       lscf->balancer.src_key,
                                       "=balancer_by_lua");
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_balancer_by_chunk(L, r);
}


static ngx_int_t
ngx_http_lua_balancer_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    u_char                  *err_msg;
    size_t                   len;
    ngx_int_t                rc;

    /* init nginx context in Lua VM */
    ngx_http_lua_set_req(L, r);

#ifndef OPENRESTY_LUAJIT
    ngx_http_lua_create_new_globals_table(L, 0 /* narr */, 1 /* nrec */);

    /*  {{{ make new env inheriting main thread's globals table */
    lua_createtable(L, 0, 1 /* nrec */);   /* the metatable for the new env */
    ngx_http_lua_get_globals_table(L);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
    /*  }}} */

    lua_setfenv(L, -2);    /*  set new running env for the code closure */
#endif /* OPENRESTY_LUAJIT */

    lua_pushcfunction(L, ngx_http_lua_traceback);
    lua_insert(L, 1);  /* put it under chunk and args */

    /*  protected call user code */
    rc = lua_pcall(L, 0, 1, 1);

    lua_remove(L, 1);  /* remove traceback function */

    dd("rc == %d", (int) rc);

    if (rc != 0) {
        /*  error occurred when running loaded code */
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
    u_char                            *cache_key = NULL;
    u_char                            *name;
    ngx_str_t                         *value;
    ngx_url_t                          url;
    ngx_http_upstream_srv_conf_t      *uscf;
    ngx_http_upstream_server_t        *us;
    ngx_http_lua_srv_conf_t           *lscf = conf;

    dd("enter");

    /* content handler setup */

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

        cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                    value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->balancer.src.data = name;
        lscf->balancer.src.len = ngx_strlen(name);

    } else {
        cache_key = ngx_http_lua_gen_chunk_cache_key(cf, "balancer_by_lua",
                                                     value[1].data,
                                                     value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        /* Don't eval nginx variables for inline lua code */
        lscf->balancer.src = value[1];
    }

    lscf->balancer.src_key = cache_key;

    /* balancer setup */

    uscf = ngx_http_conf_get_module_srv_conf(cf, ngx_http_upstream_module);

    if (uscf->servers->nelts == 0) {
        us = ngx_array_push(uscf->servers);
        if (us == NULL) {
            return NGX_CONF_ERROR;
        }

        ngx_memzero(us, sizeof(ngx_http_upstream_server_t));
        ngx_memzero(&url, sizeof(ngx_url_t));

        ngx_str_set(&url.url, "0.0.0.1");
        url.default_port = 80;

        if (ngx_parse_url(cf->pool, &url) != NGX_OK) {
            return NGX_CONF_ERROR;
        }

        us->name = url.url;
        us->addrs = url.addrs;
        us->naddrs = url.naddrs;

        ngx_http_lua_balancer_default_server_sockaddr = us->addrs[0].sockaddr;
    }

    if (uscf->peer.init_upstream) {
        ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
                           "load balancing method redefined");

        lscf->balancer.original_init_upstream = uscf->peer.init_upstream;

    } else {
        lscf->balancer.original_init_upstream =
            ngx_http_upstream_init_round_robin;
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
ngx_http_lua_balancer_init(ngx_conf_t *cf, ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_lua_srv_conf_t    *lscf;

    lscf = ngx_http_conf_upstream_srv_conf(us, ngx_http_lua_module);

    if (lscf->balancer.original_init_upstream(cf, us) != NGX_OK) {
        return NGX_ERROR;
    }

    lscf->balancer.original_init_peer = us->peer.init;

    us->peer.init = ngx_http_lua_balancer_init_peer;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_balancer_init_peer(ngx_http_request_t *r,
    ngx_http_upstream_srv_conf_t *us)
{
    ngx_http_lua_srv_conf_t            *lscf;
    ngx_http_lua_balancer_peer_data_t  *bp;

    lscf = ngx_http_conf_upstream_srv_conf(us, ngx_http_lua_module);

    if (lscf->balancer.original_init_peer(r, us) != NGX_OK) {
        return NGX_ERROR;
    }

    bp = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_balancer_peer_data_t));
    if (bp == NULL) {
        return NGX_ERROR;
    }

    bp->conf = lscf;
    bp->request = r;
    bp->data = r->upstream->peer.data;
    bp->original_get_peer = r->upstream->peer.get;
    bp->original_free_peer = r->upstream->peer.free;

    r->upstream->peer.data = bp;
    r->upstream->peer.get = ngx_http_lua_balancer_get_peer;
    r->upstream->peer.free = ngx_http_lua_balancer_free_peer;

#if (NGX_HTTP_SSL)
    bp->original_set_session = r->upstream->peer.set_session;
    bp->original_save_session = r->upstream->peer.save_session;

    r->upstream->peer.set_session = ngx_http_lua_balancer_set_session;
    r->upstream->peer.save_session = ngx_http_lua_balancer_save_session;
#endif

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_balancer_get_peer(ngx_peer_connection_t *pc, void *data)
{
    lua_State                              *L;
    ngx_int_t                               rc;
    ngx_queue_t                            *q;
    ngx_connection_t                       *c;
    ngx_http_request_t                     *r;
    ngx_http_lua_ctx_t                     *ctx;
    ngx_http_lua_srv_conf_t                *lscf;
    ngx_http_lua_balancer_keepalive_item_t *item;
    ngx_http_lua_balancer_peer_data_t      *bp = data;
    void                                   *pdata;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "lua balancer: get peer, tries: %ui", pc->tries);

    r = bp->request;
    lscf = bp->conf;

    ngx_http_lua_assert(lscf->balancer.handler && r);

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            return NGX_ERROR;
        }

        L = ngx_http_lua_get_lua_vm(r, ctx);

    } else {
        L = ngx_http_lua_get_lua_vm(r, ctx);

        dd("reset ctx");
        ngx_http_lua_reset_ctx(r, L, ctx);
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_BALANCER;

    bp->cpool = NULL;
    bp->sockaddr = NULL;
    bp->socklen = 0;
    bp->more_tries = 0;
    bp->cpool_crc32 = 0;
    bp->cpool_size = 0;
    bp->keepalive_requests = 0;
    bp->keepalive_timeout = 0;
    bp->keepalive = 0;
    bp->total_tries++;

    pdata = r->upstream->peer.data;
    r->upstream->peer.data = bp;

    rc = lscf->balancer.handler(r, lscf, L);

    r->upstream->peer.data = pdata;

    if (rc == NGX_ERROR) {
        return NGX_ERROR;
    }

    if (ctx->exited && ctx->exit_code != NGX_OK) {
        rc = ctx->exit_code;
        if (rc == NGX_ERROR
            || rc == NGX_BUSY
            || rc == NGX_DECLINED
#ifdef HAVE_BALANCER_STATUS_CODE_PATCH
            || rc >= NGX_HTTP_SPECIAL_RESPONSE
#endif
        ) {
            return rc;
        }

        if (rc > NGX_OK) {
            return NGX_ERROR;
        }
    }

    if (ngx_http_lua_balancer_peer_set(bp)) {
        pc->sockaddr = bp->sockaddr;
        pc->socklen = bp->socklen;
        pc->name = bp->host;
        pc->cached = 0;
        pc->connection = NULL;

        if (bp->more_tries) {
            r->upstream->peer.tries += bp->more_tries;
        }

        if (ngx_http_lua_balancer_keepalive_is_enabled(bp)) {
            ngx_http_lua_balancer_get_keepalive_pool(L, bp->cpool_crc32,
                                                     &bp->cpool);

            if (bp->cpool == NULL
                && ngx_http_lua_balancer_create_keepalive_pool(L, pc->log,
                                                               bp->cpool_crc32,
                                                               bp->cpool_size,
                                                               &bp->cpool)
                   != NGX_OK)
            {
                return NGX_ERROR;
            }

            ngx_http_lua_assert(bp->cpool);

            if (!ngx_queue_empty(&bp->cpool->cache)) {
                q = ngx_queue_head(&bp->cpool->cache);

                item = ngx_queue_data(q, ngx_http_lua_balancer_keepalive_item_t,
                                      queue);
                c = item->connection;

                ngx_queue_remove(q);
                ngx_queue_insert_head(&bp->cpool->free, q);

                c->idle = 0;
                c->sent = 0;
                c->log = pc->log;
                c->read->log = pc->log;
                c->write->log = pc->log;
                c->pool->log = pc->log;

                if (c->read->timer_set) {
                    ngx_del_timer(c->read);
                }

                pc->cached = 1;
                pc->connection = c;

                ngx_log_debug3(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                               "lua balancer: keepalive reusing connection %p, "
                               "requests: %ui, cpool: %p",
                               c, c->requests, bp->cpool);

                return NGX_DONE;
            }

            bp->cpool->connections++;

            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                           "lua balancer: keepalive no free connection, "
                           "cpool: %p", bp->cpool);
        }

        return NGX_OK;
    }

    rc = bp->original_get_peer(pc, bp->data);
    if (rc == NGX_ERROR) {
        return rc;
    }

    if (pc->sockaddr == ngx_http_lua_balancer_default_server_sockaddr) {
        ngx_log_error(NGX_LOG_ERR, pc->log, 0,
                      "lua balancer: no peer set");

        return NGX_ERROR;
    }

    return rc;
}


static void
ngx_http_lua_balancer_free_peer(ngx_peer_connection_t *pc, void *data,
    ngx_uint_t state)
{
    ngx_queue_t                                *q;
    ngx_connection_t                           *c;
    ngx_http_upstream_t                        *u;
    ngx_http_lua_balancer_keepalive_item_t     *item;
    ngx_http_lua_balancer_keepalive_pool_t     *cpool;
    ngx_http_lua_balancer_peer_data_t          *bp = data;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "lua balancer: free peer, tries: %ui", pc->tries);

    u = bp->request->upstream;
    c = pc->connection;

    if (ngx_http_lua_balancer_peer_set(bp)) {
        bp->last_peer_state = (int) state;

        if (pc->tries) {
            pc->tries--;
        }

        if (ngx_http_lua_balancer_keepalive_is_enabled(bp)) {
            cpool = bp->cpool;

            if (state & NGX_PEER_FAILED
                || c == NULL
                || c->read->eof
                || c->read->error
                || c->read->timedout
                || c->write->error
                || c->write->timedout)
            {
                goto invalid;
            }

            if (bp->keepalive_requests
                && c->requests >= bp->keepalive_requests)
            {
                goto invalid;
            }

            if (!u->keepalive) {
                goto invalid;
            }

            if (!u->request_body_sent) {
                goto invalid;
            }

            if (ngx_terminate || ngx_exiting) {
                goto invalid;
            }

            if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
                goto invalid;
            }

            if (ngx_queue_empty(&cpool->free)) {
                q = ngx_queue_last(&cpool->cache);
                ngx_queue_remove(q);

                item = ngx_queue_data(q, ngx_http_lua_balancer_keepalive_item_t,
                                      queue);

                ngx_http_lua_balancer_close(item->connection);

            } else {
                q = ngx_queue_head(&cpool->free);
                ngx_queue_remove(q);

                item = ngx_queue_data(q, ngx_http_lua_balancer_keepalive_item_t,
                                      queue);
            }

            ngx_log_debug3(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                           "lua balancer: keepalive saving connection %p, "
                           "cpool: %p, connections: %ui",
                           c, cpool, cpool->connections);

            ngx_queue_insert_head(&cpool->cache, q);

            item->connection = c;

            pc->connection = NULL;

            if (bp->keepalive_timeout) {
                c->read->delayed = 0;
                ngx_add_timer(c->read, bp->keepalive_timeout);

            } else if (c->read->timer_set) {
                ngx_del_timer(c->read);
            }

            if (c->write->timer_set) {
                ngx_del_timer(c->write);
            }

            c->write->handler = ngx_http_lua_balancer_dummy_handler;
            c->read->handler = ngx_http_lua_balancer_close_handler;

            c->data = item;
            c->idle = 1;
            c->log = ngx_cycle->log;
            c->read->log = ngx_cycle->log;
            c->write->log = ngx_cycle->log;
            c->pool->log = ngx_cycle->log;

            if (c->read->ready) {
                ngx_http_lua_balancer_close_handler(c->read);
            }

            return;

invalid:

            cpool->connections--;

            ngx_log_debug3(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                           "lua balancer: keepalive not saving connection %p, "
                           "cpool: %p, connections: %ui",
                           c, cpool, cpool->connections);

            if (cpool->connections == 0) {
                ngx_http_lua_balancer_free_keepalive_pool(pc->log, cpool);
            }
        }

        return;
    }

    bp->original_free_peer(pc, bp->data, state);
}


static ngx_int_t
ngx_http_lua_balancer_create_keepalive_pool(lua_State *L, ngx_log_t *log,
    uint32_t cpool_crc32, ngx_uint_t cpool_size,
    ngx_http_lua_balancer_keepalive_pool_t **cpool)
{
    size_t                                       size;
    ngx_uint_t                                   i;
    ngx_http_lua_balancer_keepalive_pool_t      *upool;
    ngx_http_lua_balancer_keepalive_item_t      *items;

    /* get upstream connection pools table */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          balancer_keepalive_pools_table_key));
    lua_rawget(L, LUA_REGISTRYINDEX); /* pools? */

    ngx_http_lua_assert(lua_istable(L, -1));

    size = sizeof(ngx_http_lua_balancer_keepalive_pool_t)
           + sizeof(ngx_http_lua_balancer_keepalive_item_t) * cpool_size;

    upool = lua_newuserdata(L, size); /* pools upool */
    if (upool == NULL) {
        return NGX_ERROR;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "lua balancer: keepalive create pool, crc32: %ui, "
                   "size: %ui", cpool_crc32, cpool_size);

    upool->lua_vm = L;
    upool->crc32 = cpool_crc32;
    upool->size = cpool_size;
    upool->connections = 0;

    ngx_queue_init(&upool->cache);
    ngx_queue_init(&upool->free);

    lua_rawseti(L, -2, cpool_crc32); /* pools */
    lua_pop(L, 1); /* orig stack */

    items = (ngx_http_lua_balancer_keepalive_item_t *) (&upool->free + 1);

    ngx_http_lua_assert((void *) items == ngx_align_ptr(items, NGX_ALIGNMENT));

    for (i = 0; i < cpool_size; i++) {
        ngx_queue_insert_head(&upool->free, &items[i].queue);
        items[i].cpool = upool;
    }

    *cpool = upool;

    return NGX_OK;
}


static void
ngx_http_lua_balancer_get_keepalive_pool(lua_State *L, uint32_t cpool_crc32,
    ngx_http_lua_balancer_keepalive_pool_t **cpool)
{
    ngx_http_lua_balancer_keepalive_pool_t      *upool;

    /* get upstream connection pools table */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          balancer_keepalive_pools_table_key));
    lua_rawget(L, LUA_REGISTRYINDEX); /* pools? */

    if (lua_isnil(L, -1)) {
        lua_pop(L, 1); /* orig stack */

        /* create upstream connection pools table */
        lua_createtable(L, 0, 0); /* pools */
        lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                              balancer_keepalive_pools_table_key));
        lua_pushvalue(L, -2); /* pools pools_table_key pools */
        lua_rawset(L, LUA_REGISTRYINDEX); /* pools */
    }

    ngx_http_lua_assert(lua_istable(L, -1));

    lua_rawgeti(L, -1, cpool_crc32); /* pools upool? */
    upool = lua_touserdata(L, -1);
    lua_pop(L, 2); /* orig stack */

    *cpool = upool;
}


static void
ngx_http_lua_balancer_free_keepalive_pool(ngx_log_t *log,
    ngx_http_lua_balancer_keepalive_pool_t *cpool)
{
    lua_State                             *L;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, log, 0,
                   "lua balancer: keepalive free pool %p, crc32: %ui",
                   cpool, cpool->crc32);

    ngx_http_lua_assert(cpool->connections == 0);

    L = cpool->lua_vm;

    /* get upstream connection pools table */
    lua_pushlightuserdata(L, ngx_http_lua_lightudata_mask(
                          balancer_keepalive_pools_table_key));
    lua_rawget(L, LUA_REGISTRYINDEX); /* pools? */

    if (lua_isnil(L, -1)) {
        lua_pop(L, 1); /* orig stack */
        return;
    }

    ngx_http_lua_assert(lua_istable(L, -1));

    lua_pushnil(L); /* pools nil */
    lua_rawseti(L, -2, cpool->crc32); /* pools */
    lua_pop(L, 1); /* orig stack */
}


static void
ngx_http_lua_balancer_close(ngx_connection_t *c)
{
    ngx_http_lua_balancer_keepalive_item_t     *item;

    item = c->data;

#if (NGX_HTTP_SSL)
    if (c->ssl) {
        c->ssl->no_wait_shutdown = 1;
        c->ssl->no_send_shutdown = 1;

        if (ngx_ssl_shutdown(c) == NGX_AGAIN) {
            c->ssl->handler = ngx_http_lua_balancer_close;
            return;
        }
    }
#endif

    ngx_destroy_pool(c->pool);
    ngx_close_connection(c);

    item->cpool->connections--;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua balancer: keepalive closing connection %p, cpool: %p, "
                   "connections: %ui",
                   c, item->cpool, item->cpool->connections);
}


static void
ngx_http_lua_balancer_dummy_handler(ngx_event_t *ev)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ev->log, 0,
                   "lua balancer: dummy handler");
}


static void
ngx_http_lua_balancer_close_handler(ngx_event_t *ev)
{
    ngx_http_lua_balancer_keepalive_item_t     *item;

    int                n;
    char               buf[1];
    ngx_connection_t  *c;

    c = ev->data;

    if (c->close || c->read->timedout) {
        goto close;
    }

    n = recv(c->fd, buf, 1, MSG_PEEK);

    if (n == -1 && ngx_socket_errno == NGX_EAGAIN) {
        ev->ready = 0;

        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            goto close;
        }

        return;
    }

close:

    item = c->data;
    c->log = ev->log;

    ngx_http_lua_balancer_close(c);

    ngx_queue_remove(&item->queue);
    ngx_queue_insert_head(&item->cpool->free, &item->queue);

    if (item->cpool->connections == 0) {
        ngx_http_lua_balancer_free_keepalive_pool(ev->log, item->cpool);
    }
}


#if (NGX_HTTP_SSL)

static ngx_int_t
ngx_http_lua_balancer_set_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_lua_balancer_peer_data_t  *bp = data;

    if (ngx_http_lua_balancer_peer_set(bp)) {
        /* TODO */
        return NGX_OK;
    }

    return bp->original_set_session(pc, bp->data);
}


static void
ngx_http_lua_balancer_save_session(ngx_peer_connection_t *pc, void *data)
{
    ngx_http_lua_balancer_peer_data_t  *bp = data;

    if (ngx_http_lua_balancer_peer_set(bp)) {
        /* TODO */
        return;
    }

    bp->original_save_session(pc, bp->data);
}

#endif


int
ngx_http_lua_ffi_balancer_set_current_peer(ngx_http_request_t *r,
    const u_char *addr, size_t addr_len, int port, unsigned int cpool_crc32,
    unsigned int cpool_size, char **err)
{
    ngx_url_t                                url;
    ngx_http_upstream_t                     *u;
    ngx_http_lua_ctx_t                      *ctx;
    ngx_http_lua_balancer_peer_data_t       *bp;

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

    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

    if (url.addrs && url.addrs[0].sockaddr) {
        bp->sockaddr = url.addrs[0].sockaddr;
        bp->socklen = url.addrs[0].socklen;
        bp->host = &url.addrs[0].name;

    } else {
        *err = "no host allowed";
        return NGX_ERROR;
    }

    bp->cpool_crc32 = (uint32_t) cpool_crc32;
    bp->cpool_size = (ngx_uint_t) cpool_size;

    return NGX_OK;
}


int
ngx_http_lua_ffi_balancer_enable_keepalive(ngx_http_request_t *r,
    unsigned long timeout, unsigned int max_requests, char **err)
{
    ngx_http_upstream_t                     *u;
    ngx_http_lua_ctx_t                      *ctx;
    ngx_http_lua_balancer_peer_data_t       *bp;

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

    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

    if (!ngx_http_lua_balancer_peer_set(bp)) {
        *err = "no current peer set";
        return NGX_ERROR;
    }

    if (!bp->cpool_crc32) {
        bp->cpool_crc32 = ngx_crc32_long(bp->host->data, bp->host->len);
    }

    bp->keepalive_timeout = (ngx_msec_t) timeout;
    bp->keepalive_requests = (ngx_uint_t) max_requests;
    bp->keepalive = 1;

    return NGX_OK;
}


int
ngx_http_lua_ffi_balancer_set_timeouts(ngx_http_request_t *r,
    long connect_timeout, long send_timeout, long read_timeout,
    char **err)
{
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_upstream_t                *u;

#if !(HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
    ngx_http_upstream_conf_t           *ucf;
    ngx_http_lua_balancer_peer_data_t  *bp;
#endif

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

#if !(HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

    if (!bp->cloned_upstream_conf) {
        /* we clone the upstream conf for the current request so that
         * we do not affect other requests at all. */

        ucf = ngx_palloc(r->pool, sizeof(ngx_http_upstream_conf_t));

        if (ucf == NULL) {
            *err = "no memory";
            return NGX_ERROR;
        }

        ngx_memcpy(ucf, u->conf, sizeof(ngx_http_upstream_conf_t));

        u->conf = ucf;
        bp->cloned_upstream_conf = 1;

    } else {
        ucf = u->conf;
    }
#endif

    if (connect_timeout > 0) {
#if (HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
        u->connect_timeout = (ngx_msec_t) connect_timeout;
#else
        ucf->connect_timeout = (ngx_msec_t) connect_timeout;
#endif
    }

    if (send_timeout > 0) {
#if (HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
        u->send_timeout = (ngx_msec_t) send_timeout;
#else
        ucf->send_timeout = (ngx_msec_t) send_timeout;
#endif
    }

    if (read_timeout > 0) {
#if (HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
        u->read_timeout = (ngx_msec_t) read_timeout;
#else
        ucf->read_timeout = (ngx_msec_t) read_timeout;
#endif
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_balancer_set_more_tries(ngx_http_request_t *r,
    int count, char **err)
{
#if (nginx_version >= 1007005)
    ngx_uint_t                          max_tries, total;
#endif
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_upstream_t                *u;
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

    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

#if (nginx_version >= 1007005)
    max_tries = r->upstream->conf->next_upstream_tries;
    total = bp->total_tries + r->upstream->peer.tries - 1;

    if (max_tries && total + count > max_tries) {
        count = max_tries - total;
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
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_upstream_t                *u;
    ngx_http_upstream_state_t          *state;
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

    bp = (ngx_http_lua_balancer_peer_data_t *) u->peer.data;

    if (r->upstream_states && r->upstream_states->nelts > 1) {
        state = r->upstream_states->elts;
        *status = (int) state[r->upstream_states->nelts - 2].status;

    } else {
        *status = 0;
    }

    return bp->last_peer_state;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
