
/*
 * Copyright (C) Chenglong Zhang (kone)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_balancer_ssl_session_storeby.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_balancer.h"


#if (NGX_HTTP_SSL)
static ngx_int_t ngx_http_lua_balancer_ssl_sess_store_by_chunk(lua_State *L,
    ngx_http_request_t *r);


ngx_int_t
ngx_http_lua_balancer_ssl_sess_store_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t  rc;

    rc = ngx_http_lua_cache_loadfile(r->connection->log, L,
                                     lscf->balancer.ssl_sess_store_src.data,
                                     lscf->balancer.ssl_sess_store_src_key);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_balancer_ssl_sess_store_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_balancer_ssl_sess_store_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t  rc;

    rc = ngx_http_lua_cache_loadbuffer(r->connection->log, L,
                                       lscf->balancer.ssl_sess_store_src.data,
                                       lscf->balancer.ssl_sess_store_src.len,
                                       lscf->balancer.ssl_sess_store_src_key,
                                       "=balancer_ssl_session_store_by_lua");

    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_balancer_ssl_sess_store_by_chunk(L, r);
}


void
ngx_http_lua_balancer_ssl_sess_store(ngx_peer_connection_t *pc, void *data)
{
    lua_State                          *L;
    ngx_int_t                           rc;
    ngx_http_request_t                 *r;
    ngx_http_lua_ctx_t                 *ctx;
    ngx_http_lua_srv_conf_t            *lscf;
    ngx_http_lua_balancer_peer_data_t  *bp = data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, pc->log, 0,
                   "balancer ssl session store");

    lscf = bp->conf;

    r = bp->request;

    ngx_http_lua_assert(lscf->balancer.ssl_sess_store_handler && r);

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            return;
        }

        L = ngx_http_lua_get_lua_vm(r, ctx);

    } else {
        L = ngx_http_lua_get_lua_vm(r, ctx);

        dd("reset ctx");
        ngx_http_lua_reset_ctx(r, L, ctx);
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_BALANCER_SSL_SESS_STORE;

    rc = lscf->balancer.ssl_sess_store_handler(r, lscf, L);

    if (rc == NGX_ERROR) {
        return;
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
            return;
        }

        if (rc > NGX_OK) {
            return;
        }
    }

    return;
}


char *
ngx_http_lua_balancer_ssl_sess_store_by_lua_block(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf)
{
    char *rv;
    ngx_conf_t save;

    save = *cf;
    cf->handler = ngx_http_lua_balancer_ssl_sess_store_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_balancer_ssl_sess_store_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                        *p;
    u_char                        *name;
    ngx_str_t                     *value;
    ngx_http_lua_srv_conf_t       *lscf = conf;

    dd("enter");

    /*  must specify a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if(lscf->balancer.ssl_sess_store_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    lscf->balancer.ssl_sess_store_handler =
                    (ngx_http_lua_srv_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_balancer_ssl_sess_store_handler_file) {
        /* Lua code in an external file */

        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
            value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->balancer.ssl_sess_store_src.data = name;
        lscf->balancer.ssl_sess_store_src.len = ngx_strlen(name);

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->balancer.ssl_sess_store_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

    } else {
        /* inlined Lua code */

        lscf->balancer.ssl_sess_store_src = value[1];

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->balancer.ssl_sess_store_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_lua_balancer_ssl_sess_store_by_chunk(lua_State *L,
    ngx_http_request_t *r)
{
    u_char                  *err_msg;
    size_t                   len;
    ngx_int_t                rc;

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
        /*  error occurred when running loaded code */
        err_msg = (u_char *) lua_tolstring(L, -1, &len);

        if (err_msg == NULL) {
            err_msg = (u_char *) "unknown reason";
            len = sizeof("unknown reason") - 1;
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "failed to run balancer_ssl_session_store_by_lua*: %*s",
                      len, err_msg);

        lua_settop(L, 0); /*  clear remaining elems on stack */

        return NGX_ERROR;
    }

    lua_settop(L, 0); /*  clear remaining elems on stack */
    return rc;
}


void
ngx_http_lua_ffi_ssl_free_session(void *session)
{
    ngx_ssl_free_session(session);
}


int
ngx_http_lua_ffi_ssl_set_upstream_session(ngx_http_request_t *r, void *session,
    char **err)
{
    if (r->upstream == NULL
        || r->upstream->peer.connection == NULL
        || r->upstream->peer.connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    return ngx_ssl_set_session(r->upstream->peer.connection, session);
}


int
ngx_http_lua_ffi_ssl_get_upstream_session(ngx_http_request_t *r,
    void **session, char **err)
{
    ngx_ssl_session_t *ssl_session;

    if (r->upstream == NULL
        || r->upstream->peer.connection == NULL
        || r->upstream->peer.connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_session = ngx_ssl_get_session(r->upstream->peer.connection);

    *session = ssl_session;

    return NGX_OK;
}

#endif  /* NGX_HTTP_SSL */
