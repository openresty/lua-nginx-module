
/*
 * Based on ngx_http_lua_ssl_certby.c and ngx_http_lua_ssl_session_storeby.c
 * by Yichun Zhang (agentzh)
 *
 * Author: Tuure Vartiainen (vartiait)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#if (NGX_HTTP_SSL)

#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_initworkerby.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_ssl_module.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_ssl_pskby.h"
#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_ssl.h"
#include "ngx_http_lua_socket_tcp.h"


static u_char *ngx_http_lua_log_ssl_psk_error(ngx_log_t *log, u_char *buf,
    size_t len);
static ngx_int_t ngx_http_lua_ssl_psk_by_chunk(lua_State *L,
    ngx_http_request_t *r);


ngx_int_t
ngx_http_lua_ssl_psk_server_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadfile(r->connection->log, L,
                                     lscf->srv.ssl_psk_src.data,
                                     lscf->srv.ssl_psk_src_key);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_ssl_psk_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_ssl_psk_server_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadbuffer(r->connection->log, L,
                                       lscf->srv.ssl_psk_src.data,
                                       lscf->srv.ssl_psk_src.len,
                                       lscf->srv.ssl_psk_src_key,
                                       "=ssl_psk_by_lua");
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_ssl_psk_by_chunk(L, r);
}


char *
ngx_http_lua_ssl_psk_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_ssl_psk_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_ssl_psk_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
#if OPENSSL_VERSION_NUMBER < 0x1000100fL

    ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                  "at least OpenSSL 1.0.1 required but found "
                  OPENSSL_VERSION_TEXT);

    return NGX_CONF_ERROR;

#else

    u_char                      *p;
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_srv_conf_t    *lscf = conf;

    /*  must specify a concrete handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lscf->srv.ssl_psk_handler) {
        return "is duplicate";
    }

    if (ngx_http_lua_ssl_init(cf->log) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;

    lscf->srv.ssl_psk_handler = (ngx_http_lua_srv_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_ssl_psk_server_handler_file) {
        /* Lua code in an external file */

        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->srv.ssl_psk_src.data = name;
        lscf->srv.ssl_psk_src.len = ngx_strlen(name);

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->srv.ssl_psk_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

    } else {
        /* inlined Lua code */

        lscf->srv.ssl_psk_src = value[1];

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->srv.ssl_psk_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';
    }

    return NGX_CONF_OK;

#endif  /* OPENSSL_VERSION_NUMBER < 0x1000205fL */
}


unsigned int ngx_http_lua_ssl_psk_server_handler(ngx_ssl_conn_t *ssl_conn,
    const char *identity, unsigned char *psk, unsigned int max_psk_len)
{
    lua_State                       *L;
    ngx_int_t                        rc;
    ngx_connection_t                *c, *fc;
    ngx_http_request_t              *r = NULL;
    ngx_http_connection_t           *hc;
    ngx_http_lua_srv_conf_t         *lscf;
    ngx_http_core_loc_conf_t        *clcf;
    ngx_http_lua_ssl_ctx_t          *cctx;

    c = ngx_ssl_get_connection(ssl_conn);

    dd("c = %p", c);

    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);

    dd("ssl server psk handler, psk-ctx=%p", cctx);

    hc = c->data;

    fc = ngx_http_lua_create_fake_connection(NULL);
    if (fc == NULL) {
        goto failed;
    }

    fc->log->handler = ngx_http_lua_log_ssl_psk_error;
    fc->log->data = fc;

    fc->addr_text = c->addr_text;
    fc->listening = c->listening;

    r = ngx_http_lua_create_fake_request(fc);
    if (r == NULL) {
        goto failed;
    }

    r->main_conf = hc->conf_ctx->main_conf;
    r->srv_conf = hc->conf_ctx->srv_conf;
    r->loc_conf = hc->conf_ctx->loc_conf;

    fc->log->file = c->log->file;
    fc->log->log_level = c->log->log_level;
    fc->ssl = c->ssl;

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

#if defined(nginx_version) && nginx_version >= 1003014

#   if nginx_version >= 1009000

    ngx_set_connection_log(fc, clcf->error_log);

#   else

    ngx_http_set_connection_log(fc, clcf->error_log);

#   endif

#else

    fc->log->file = clcf->error_log->file;

    if (!(fc->log->log_level & NGX_LOG_DEBUG_CONNECTION)) {
        fc->log->log_level = clcf->error_log->log_level;
    }

#endif

    if (cctx == NULL) {
        cctx = ngx_pcalloc(c->pool, sizeof(ngx_http_lua_ssl_ctx_t));
        if (cctx == NULL) {
            goto failed;  /* error */
        }
    }

    if (identity == NULL) {
        ngx_ssl_error(NGX_LOG_ALERT, c->log, 0,
            "client did not send TLS-PSK identity");
        goto failed;
    }

    cctx->exit_code = 0;  /* unsuccessful by default */
    cctx->connection = c;
    cctx->request = r;
    cctx->psk_identity.data = (u_char *) identity;
    cctx->psk_identity.len = ngx_strlen(identity);
    cctx->done = 0;

    dd("setting cctx = %p", cctx);

    if (SSL_set_ex_data(c->ssl->connection, ngx_http_lua_ssl_ctx_index, cctx)
        == 0)
    {
        ngx_ssl_error(NGX_LOG_ALERT, c->log, 0, "SSL_set_ex_data() failed");
        goto failed;
    }

    lscf = ngx_http_get_module_srv_conf(r, ngx_http_lua_module);

    /* TODO honor lua_code_cache off */
    L = ngx_http_lua_get_lua_vm(r, NULL);

    c->log->action = "setting SSL PSK by lua";

    rc = lscf->srv.ssl_psk_handler(r, lscf, L);

    if (rc >= NGX_OK || rc == NGX_ERROR) {
        cctx->done = 1;

        if (cctx->cleanup) {
            *cctx->cleanup = NULL;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "lua_psk_by_lua: handler return value: %i, "
                       "psk server cb exit code: %d", rc, cctx->exit_code);

        c->log->action = "SSL handshaking";

        if (rc == NGX_ERROR) {
            /* 0 == unknown_psk_identity */
            return cctx->exit_code;
        }

        if (cctx->psk_key.data == NULL) {
            ngx_ssl_error(NGX_LOG_ALERT, c->log, 0, "psk_key.data == NULL");

            return cctx->exit_code;
        }

        if (cctx->psk_key.len == 0) {
            ngx_ssl_error(NGX_LOG_ALERT, c->log, 0, "psk_key.len == 0");

            return cctx->exit_code;
        }

        if (cctx->psk_key.len > (size_t) max_psk_len) {
            ngx_ssl_error(NGX_LOG_ALERT, c->log, 0,
                "psk_key.len: %i > max_psk_len: %i",
                    cctx->psk_key.len, max_psk_len);

            return cctx->exit_code;
        }

        ngx_memcpy(psk, cctx->psk_key.data, cctx->psk_key.len);
        cctx->exit_code = cctx->psk_key.len;

        /* return length of psk key */
        return cctx->exit_code;
    }

    /* impossible to reach here */
    ngx_http_lua_assert(0);

failed:

    if (r && r->pool) {
        ngx_http_lua_free_fake_request(r);
    }

    if (fc) {
        ngx_http_lua_close_fake_connection(fc);
    }

    return 0;
}


unsigned int ngx_http_lua_ssl_psk_client_handler(ngx_ssl_conn_t *ssl_conn,
    const char *hint, char *identity, unsigned int max_identity_len,
    unsigned char *psk, unsigned int max_psk_len)
{
    ngx_connection_t                *c;
    ngx_connection_t                *dc;  /* downstream connection */
    ngx_http_request_t              *r = NULL;
    ngx_http_lua_loc_conf_t         *llcf;

    ngx_http_lua_socket_tcp_upstream_t  *u;

    c = ngx_ssl_get_connection(ssl_conn);

    if (c == NULL) {
        goto failed;
    }

    dd("ssl psk client handler, c = %p", c);

    u = c->data;

    if (u == NULL) {
        ngx_ssl_error(NGX_LOG_ALERT, c->log, 0, "no upstream socket found");
        goto failed;
    }

    r = u->request;

    if (r == NULL) {
        ngx_ssl_error(NGX_LOG_ALERT, c->log, 0, "no http request found");
        goto failed;
    }

    dc = r->connection;

    if (dc == NULL) {
        ngx_ssl_error(NGX_LOG_ALERT, c->log, 0, "no downstream socket found");
        goto failed;
    }

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf == NULL) {
        ngx_ssl_error(NGX_LOG_ALERT, dc->log, 0,
            "getting module loc conf failed");
        goto failed;
    }

    if (hint == NULL) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "sslhandshake: psk server hint was null");
    }
    else {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "sslhandshake: psk server hint: %s", hint);

        size_t hint_len = ngx_strlen(hint);
        if (u->ssl_psk_identity_hint.data) {
            /* buffer already allocated */

            if (u->ssl_psk_identity_hint.len > hint_len) {
                /* reuse it */
                ngx_memcpy(u->ssl_psk_identity_hint.data, hint, hint_len);
                u->ssl_psk_identity_hint.len = hint_len;
            } else {
                ngx_free(u->ssl_psk_identity_hint.data);
                goto new_ssl_psk_identity_hint;
            }
        }
        else {

new_ssl_psk_identity_hint:

            u->ssl_psk_identity_hint.data = ngx_alloc(hint_len + 1,
                                                      ngx_cycle->log);
            if (u->ssl_psk_identity_hint.data == NULL) {
                u->ssl_psk_identity_hint.len = 0;

                ngx_ssl_error(NGX_LOG_ALERT, dc->log, 0,
                    "could not allocate memory for ssl_psk_identity_hint");
                goto failed;
            }

            ngx_memcpy(u->ssl_psk_identity_hint.data, hint, hint_len);
            u->ssl_psk_identity_hint.len = hint_len;
        }
    }

    if (llcf->ssl_psk_identity.len) {
        if (llcf->ssl_psk_identity.len <= max_identity_len) {
            ngx_snprintf((u_char *) identity, max_identity_len, "%V",
                         &llcf->ssl_psk_identity);
        }
        else {
            ngx_ssl_error(NGX_LOG_ALERT, dc->log, 0,
                          "ssl_psk_identity.len: %i > max_identity_len: %i",
                          llcf->ssl_psk_identity.len, max_identity_len);
            goto failed;
        }
    }
    else {
        ngx_ssl_error(NGX_LOG_ALERT, dc->log, 0,
                      "no ssl_psk_identity defined");
        goto failed;
    }

    if (llcf->ssl_psk_key.len) {
        if (llcf->ssl_psk_key.len <= max_psk_len) {
            ngx_memcpy(psk, llcf->ssl_psk_key.data, llcf->ssl_psk_key.len);
            return llcf->ssl_psk_key.len;
        }
        else {
            ngx_ssl_error(NGX_LOG_ALERT, dc->log, 0,
                          "ssl_psk_key.len: %i > max_psk_len: %i",
                          llcf->ssl_psk_key.len, max_psk_len);
            goto failed;
        }
    }
    else {
        ngx_ssl_error(NGX_LOG_ALERT, dc->log, 0, "no ssl_psk_key defined");
        goto failed;
    }

    /* impossible to reach here */
    ngx_http_lua_assert(0);

failed:

    return 0;
}

static u_char *
ngx_http_lua_log_ssl_psk_error(ngx_log_t *log, u_char *buf, size_t len)
{
    u_char              *p;
    ngx_connection_t    *c;

    if (log->action) {
        p = ngx_snprintf(buf, len, " while %s", log->action);
        len -= p - buf;
        buf = p;
    }

    p = ngx_snprintf(buf, len, ", context: ssl_psk_by_lua*");
    len -= p - buf;
    buf = p;

    c = log->data;

    if (c->addr_text.len) {
        p = ngx_snprintf(buf, len, ", client: %V", &c->addr_text);
        len -= p - buf;
        buf = p;
    }

    if (c && c->listening && c->listening->addr_text.len) {
        p = ngx_snprintf(buf, len, ", server: %V", &c->listening->addr_text);
        /* len -= p - buf; */
        buf = p;
    }

    return buf;
}


static ngx_int_t
ngx_http_lua_ssl_psk_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    size_t                   len;
    u_char                  *err_msg;
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

    ctx->entered_content_phase = 1;
    ctx->context = NGX_HTTP_LUA_CONTEXT_SSL_PSK;

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
                      "failed to run ssl_psk_by_lua*: %*s", len, err_msg);

        lua_settop(L, 0); /*  clear remaining elems on stack */
        ngx_http_lua_finalize_request(r, rc);

        return NGX_ERROR;
    }

    /* rc == 0 */
    rc = (ngx_int_t) lua_tointeger(L, -1);
    dd("got return value: %d", (int) rc);

    if (rc != NGX_OK) {
        rc = NGX_ERROR;
    }

    lua_settop(L, 0); /*  clear remaining elems on stack */
    ngx_http_lua_finalize_request(r, rc);
    return rc;
}


#ifndef NGX_LUA_NO_FFI_API

/* set psk key from key to lua context. */
int
ngx_http_lua_ffi_ssl_set_psk_key(ngx_http_request_t *r,
    const char *key, size_t len, char **err)
{
    u_char                          *buf;
    ngx_connection_t                *c;
    ngx_ssl_conn_t                  *ssl_conn;
    ngx_http_lua_ssl_ctx_t          *cctx;

    c = r->connection;

    if (c == NULL || c->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = c->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    dd("set cctx psk key");
    cctx = ngx_http_lua_ssl_get_ctx(ssl_conn);
    if (cctx == NULL) {
        *err = "bad lua context";
        return NGX_ERROR;
    }

    buf = ngx_palloc(cctx->connection->pool, len);
    if (buf == NULL) {
        *err = "unable to alloc memory for buffer";
        return NGX_ERROR;
    }
    ngx_memcpy(buf, key, len);

    cctx->psk_key.data = buf;
    cctx->psk_key.len = len;

    return NGX_OK;
}


/* get psk identity from lua context into buf.
 * the memory allocation of buf should be handled externally. */
int
ngx_http_lua_ffi_ssl_get_psk_identity(ngx_http_request_t *r,
    char *buf, char **err)
{
    int                              id_len;
    u_char                          *id;
    ngx_connection_t                *c;
    ngx_ssl_conn_t                  *ssl_conn;
    ngx_http_lua_ssl_ctx_t          *cctx;

    c = r->connection;

    if (c == NULL || c->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = c->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    dd("get cctx psk identity");
    cctx = ngx_http_lua_ssl_get_ctx(ssl_conn);
    if (cctx == NULL) {
        *err = "bad lua context";
        return NGX_ERROR;
    }

    id = cctx->psk_identity.data;
    if (id == NULL) {
        *err = "uninitialized psk identity in lua context";
        return NGX_ERROR;
    }

    id_len = cctx->psk_identity.len;
    if (id_len == 0) {
        *err = "uninitialized psk identity len in lua context";
        return NGX_ERROR;
    }

    ngx_memcpy(buf, id, id_len);

    return NGX_OK;
}


/* return the size of psk identity. */
int
ngx_http_lua_ffi_ssl_get_psk_identity_size(ngx_http_request_t *r,
    char **err)
{
    ngx_connection_t                *c;
    ngx_ssl_conn_t                  *ssl_conn;
    ngx_http_lua_ssl_ctx_t          *cctx;

    c = r->connection;

    if (c == NULL || c->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = c->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    dd("get cctx psk identity");
    cctx = ngx_http_lua_ssl_get_ctx(ssl_conn);
    if (cctx == NULL) {
        *err = "bad lua context";
        return NGX_ERROR;
    }

    if (cctx->psk_identity.len == 0) {
        *err = "uninitialized psk identity len in lua context";
        return NGX_ERROR;
    }

    return cctx->psk_identity.len;
}


#endif  /* NGX_LUA_NO_FFI_API */


#endif /* NGX_HTTP_SSL */
