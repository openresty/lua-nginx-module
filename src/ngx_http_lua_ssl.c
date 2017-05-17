
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#if (NGX_HTTP_SSL)


static size_t ngx_http_lua_ssl_get_error(u_long e, u_char *ssl_err,
    size_t ssl_err_len, const char *default_err, size_t default_err_len);


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


static size_t
ngx_http_lua_ssl_get_error(u_long e, u_char *ssl_err,
    size_t ssl_err_len, const char *default_err, size_t default_err_len)
{
    size_t             len;

    if (e == 0) {
        len = ngx_min(ssl_err_len, default_err_len);
        ngx_memcpy(ssl_err, default_err, len);

        return len;
    }

    ERR_error_string_n(e, (char *) ssl_err, ssl_err_len);

    return ngx_strlen(ssl_err);
}


#ifndef NGX_LUA_NO_FFI_API


void *
ngx_http_lua_ffi_ssl_ctx_init(ngx_uint_t protocols, char **err)
{
    ngx_ssl_t           ssl;

    ssl.log = ngx_cycle->log;
    if (ngx_ssl_create(&ssl, protocols, NULL) != NGX_OK) {
        *err = "failed to create ssl ctx";
        return NULL;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ssl.log, 0, "lua ssl ctx init: %p:%d",
                   ssl.ctx, ssl.ctx->references);

    return ssl.ctx;
}


int
ngx_http_lua_ffi_ssl_ctx_set_cert(void *cdata_ctx, void *cdata_cert,
    u_char *err, size_t *err_len)
{
    int                 num;
    size_t              n;
    u_long              e;
    const char         *default_err;

#ifdef LIBRESSL_VERSION_NUMBER

    default_err = "LibreSSL not supported";
    goto failed;

#else

#   if OPENSSL_VERSION_NUMBER < 0x1000205fL

    default_err = "at least OpenSSL 1.0.2e required but found "
                  OPENSSL_VERSION_TEXT;
    goto failed;

#   else

    X509               *x509 = NULL;
    SSL_CTX            *ssl_ctx = cdata_ctx;
    STACK_OF(X509)     *cert = cdata_cert;

#   ifdef OPENSSL_IS_BORINGSSL
    size_t              i;
#   else
    int                 i;
#   endif

    num = sk_X509_num(cert);
    if (num < 1) {
        default_err = "sk_X509_num() failed";
        goto failed;
    }

    x509 = sk_X509_value(cert, 0);
    if (x509 == NULL) {
        default_err = "sk_X509_value() failed";
        goto failed;
    }

    if (SSL_CTX_use_certificate(ssl_ctx, x509) == 0) {
        default_err = "SSL_CTX_use_certificate() failed";
        goto failed;
    }

    /* read rest of the chain */

    for (i = 1; i < num; i++) {

        x509 = sk_X509_value(cert, i);
        if (x509 == NULL) {
            default_err = "sk_X509_value() failed";
            goto failed;
        }

        if (SSL_CTX_add1_chain_cert(ssl_ctx, x509) == 0) {
            default_err = "SSL_add1_chain_cert() failed";
            goto failed;
        }
    }

    return NGX_OK;

#   endif  /* OPENSSL_VERSION_NUMBER < 0x1000205fL */
#endif

failed:

    e = ERR_get_error();
    n = ngx_strlen(default_err);
    *err_len = ngx_http_lua_ssl_get_error(e, err, *err_len, default_err, n);

    return NGX_ERROR;
}


int
ngx_http_lua_ffi_ssl_ctx_set_priv_key(void *cdata_ctx, void *cdata_key,
    u_char *err, size_t *err_len)
{
    SSL_CTX            *ssl_ctx = cdata_ctx;
    EVP_PKEY           *key = cdata_key;

    size_t              n;
    u_long              e;
    const char         *default_err;

    if (SSL_CTX_use_PrivateKey(ssl_ctx, key) == 0) {
        default_err = "SSL_CTX_use_PrivateKey() failed";
        goto failed;
    }

    return NGX_OK;

failed:

    e = ERR_get_error();
    n = ngx_strlen(default_err);
    *err_len = ngx_http_lua_ssl_get_error(e, err, *err_len, default_err, n);

    return NGX_ERROR;
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
