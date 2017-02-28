
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#if (NGX_HTTP_SSL)


int ngx_http_lua_ssl_ctx_index = -1;


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

    return NGX_OK;
}


#ifndef NGX_LUA_NO_FFI_API


void *
ngx_http_lua_ffi_ssl_ctx_init(ngx_uint_t protocols, char **err)
{
    ngx_ssl_t                ssl;

    ssl.log = ngx_cycle->log;
    if (ngx_ssl_create(&ssl, protocols, NULL) != NGX_OK) {
        *err = "failed to create ssl ctx";
        ngx_log_error(NGX_LOG_ERR, ssl.log, 0, *err);
        return NULL;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ssl.log, 0,
                   "lua ssl ctx init: %p:%d", ssl.ctx, ssl.ctx->references);

    return ssl.ctx;
}


int
ngx_http_lua_ffi_ssl_ctx_set_cert(void *cdata_ctx, void *cdata_cert, char **err)
{
#ifdef LIBRESSL_VERSION_NUMBER

    *err = "LibreSSL not supported";
    return NGX_ERROR;

#else

#   if OPENSSL_VERSION_NUMBER < 0x1000205fL

    *err = "at least OpenSSL 1.0.2e required but found " OPENSSL_VERSION_TEXT;
    return NGX_ERROR;

#   else

    X509              *x509 = NULL;
    SSL_CTX           *ssl_ctx = cdata_ctx;
    STACK_OF(X509)    *cert = cdata_cert;

#ifdef OPENSSL_IS_BORINGSSL
    size_t             i;
#else
    int                i;
#endif

    if (sk_X509_num(cert) < 1) {
        *err = "sk_X509_num() failed";
        ngx_ssl_error(NGX_LOG_ERR, ngx_cycle->log, 0, *err);
        return NGX_ERROR;
    }

    x509 = sk_X509_value(cert, 0);
    if (x509 == NULL) {
        *err = "sk_X509_value() failed";
        ngx_ssl_error(NGX_LOG_ERR, ngx_cycle->log, 0, *err);
        return NGX_ERROR;
    }

    if (SSL_CTX_use_certificate(ssl_ctx, x509) == 0) {
        *err = "SSL_CTX_use_certificate() failed";
        ngx_ssl_error(NGX_LOG_ERR, ngx_cycle->log, 0, *err);
        return NGX_ERROR;
    }

    /* read rest of the chain */

    for (i = 1; i < sk_X509_num(cert); i++) {

        x509 = sk_X509_value(cert, i);
        if (x509 == NULL) {
            *err = "sk_X509_value() failed";
            ngx_ssl_error(NGX_LOG_ERR, ngx_cycle->log, 0, *err);
            return NGX_ERROR;
        }

        if (SSL_CTX_add1_chain_cert(ssl_ctx, x509) == 0) {
            *err = "SSL_add1_chain_cert() failed";
            ngx_ssl_error(NGX_LOG_ERR, ngx_cycle->log, 0, *err);
            return NGX_ERROR;
        }
    }

    return NGX_OK;

#   endif  /* OPENSSL_VERSION_NUMBER < 0x1000205fL */
#endif
}


int
ngx_http_lua_ffi_ssl_ctx_set_priv_key(void *cdata_ctx, void *cdata_key,
    char **err)
{
    SSL_CTX     *ssl_ctx = cdata_ctx;
    EVP_PKEY    *key = cdata_key;

    if (SSL_CTX_use_PrivateKey(ssl_ctx, key) == 0) {
        *err = "SSL_CTX_use_PrivateKey() failed";
        ngx_ssl_error(NGX_LOG_ERR, ngx_cycle->log, 0, *err);
        return NGX_ERROR;
    }

    return NGX_OK;
}


void
ngx_http_lua_ffi_ssl_ctx_free(void *cdata)
{
    SSL_CTX *ssl_ctx = cdata;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log,
                   0, "lua ssl ctx free: %p:%d", ssl_ctx, ssl_ctx->references);

    SSL_CTX_free(ssl_ctx);
}


#endif /* NGX_LUA_NO_FFI_API */


#endif /* NGX_HTTP_SSL */
