
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
    cctx->entered_psk_handler = 1;
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

    rc = lscf->srv.ssl_cert_handler(r, lscf, L);

    if (rc >= NGX_OK || rc == NGX_ERROR) {
        cctx->done = 1;

        if (cctx->cleanup) {
            *cctx->cleanup = NULL;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "lua_certificate_by_lua: handler return value: %i, "
                       "psk server cb exit code: %d", rc, cctx->exit_code);

        c->log->action = "SSL handshaking";

        if (rc == NGX_ERROR || cctx->exit_code != NGX_OK) {
            /* 0 == unknown_psk_identity */
            return 0;
        }

        if (cctx->psk_key.data == NULL) {
            ngx_ssl_error(NGX_LOG_ALERT, c->log, 0, "psk_key.data == NULL");

            return 0;
        }

        if (cctx->psk_key.len == 0) {
            ngx_ssl_error(NGX_LOG_ALERT, c->log, 0, "psk_key.len == 0");

            return 0;
        }

        if (cctx->psk_key.len > (size_t) max_psk_len) {
            ngx_ssl_error(NGX_LOG_ALERT, c->log, 0,
                "psk_key.len: %i > max_psk_len: %i",
                    cctx->psk_key.len, max_psk_len);

            return 0;
        }

        ngx_memcpy(psk, cctx->psk_key.data, cctx->psk_key.len);

        /* return length of psk key */
        return cctx->psk_key.len;
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

    if(!cctx->entered_psk_handler) {
        *err = "not in psk context";
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

    if(!cctx->entered_psk_handler) {
        *err = "not in psk context";
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
