
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#if (NGX_HTTP_SSL)

#include "ngx_http_lua_ssl.h"


int ngx_http_lua_ssl_ctx_index = -1;
int ngx_http_lua_ssl_key_log_index = -1;


ngx_int_t
ngx_http_lua_ssl_init(ngx_log_t *log)
{
    if (ngx_http_lua_ssl_ctx_index == -1) {
        ngx_http_lua_ssl_ctx_index = SSL_get_ex_new_index(0, NULL, NULL,
                                                          NULL, NULL);

        if (ngx_http_lua_ssl_ctx_index == -1) {
            ngx_ssl_error(NGX_LOG_ALERT, log, 0,
                          "lua: SSL_get_ex_new_index() for ctx failed");
            return NGX_ERROR;
        }
    }

    if (ngx_http_lua_ssl_key_log_index == -1) {
        ngx_http_lua_ssl_key_log_index = SSL_get_ex_new_index(0, NULL, NULL,
                                                              NULL, NULL);

        if (ngx_http_lua_ssl_key_log_index == -1) {
            ngx_ssl_error(NGX_LOG_ALERT, log, 0,
                          "lua: SSL_get_ex_new_index() for key log failed");
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


ngx_ssl_conn_t *
ngx_http_lua_ffi_get_upstream_ssl_pointer(ngx_http_request_t *r,
    const char **err)
{
    ngx_connection_t  *c;

    if (r == NULL) {
        *err = "bad request";
        return NULL;
    }

    if (r->upstream == NULL) {
        *err = "bad upstream";
        return NULL;
    }

    if (r->upstream->peer.connection == NULL) {
        *err = "bad peer connection";
        return NULL;
    }

    c = r->upstream->peer.connection;

    if (c->ssl == NULL || c->ssl->connection == NULL) {
        *err = "not ssl connection";
        return NULL;
    }

    return c->ssl->connection;
}


#endif /* NGX_HTTP_SSL */
