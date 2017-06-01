
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
ngx_http_lua_ffi_ssl_ctx_set_cert_store(void *cdata_ctx, void *cdata_store,
    int up_ref, unsigned char *err, size_t *err_len)
{
    SSL_CTX            *ssl_ctx = cdata_ctx;
    X509_STORE         *x509_store = cdata_store;

    size_t              n;
    u_long              e;
    const char         *default_err;

    /*
     * Note: If another X509_STORE object is currently set in ctx,
     *       it will be X509_STORE_free()ed
     */

    SSL_CTX_set_cert_store(ssl_ctx, x509_store);

    if (up_ref == 0) {
        return NGX_OK;
    }

    /*
     * X509_STORE_up_ref() require OpenSSL at least 1.1.0, so we use CRYPTO_add
     * to implement X509_STORE_up_ref
     */

    if (CRYPTO_add(&x509_store->references, 1, CRYPTO_LOCK_X509_STORE) < 2) {
        default_err = "X509_STORE_up_ref() failed";
        goto failed;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua ssl x509 store up reference: %p:%d", x509_store,
                   x509_store->references);

    return NGX_OK;

failed:

    e = ERR_get_error();
    n = ngx_strlen(default_err);
    *err_len = ngx_http_lua_ssl_get_error(e, err, *err_len, default_err, n);

    return NGX_ERROR;
}


int
ngx_http_lua_ffi_ssl_ctx_add_ca_cert(void *cdata_ctx, const u_char *cert,
    size_t size, unsigned char *err, size_t *err_len)
{
    BIO                *bio = NULL;
    SSL_CTX            *ssl_ctx = cdata_ctx;

    X509               *x509;
    size_t              n;
    u_long              e;
    const char         *default_err;
    X509_STORE         *store;

    bio = BIO_new_mem_buf(cert, size);
    if (bio == NULL) {
        default_err = "BIO_new_mem_buf() failed";
        goto failed;
    }

    store = SSL_CTX_get_cert_store(ssl_ctx);
    if (store == NULL) {

        store = X509_STORE_new();
        if (store == NULL) {
            default_err = "X509_STORE_new() failed";
            goto failed;
        }

        SSL_CTX_set_cert_store(ssl_ctx, store);
    }

    for (;;) {
        x509 = PEM_read_bio_X509(bio, NULL, NULL, NULL);
        if (x509 == NULL) {
            n = ERR_peek_last_error();

            if (ERR_GET_LIB(n) == ERR_LIB_PEM
                && ERR_GET_REASON(n) == PEM_R_NO_START_LINE)
            {
                /* end of file */
                ERR_clear_error();
                break;
            }

            default_err = "PEM_read_bio_X509() failed";
            goto failed;
        }

        if (!X509_STORE_add_cert(store, x509)) {
            X509_free(x509);
            default_err = "X509_STORE_add_cert() failed";
            goto failed;
        }

        X509_free(x509);
    }

    BIO_free_all(bio);

    return NGX_OK;

failed:

    if(bio != NULL) {
        BIO_free_all(bio);
    }

    e = ERR_get_error();
    n = ngx_strlen(default_err);
    *err_len = ngx_http_lua_ssl_get_error(e, err, *err_len, default_err, n);

    return NGX_ERROR;
}


int
ngx_http_lua_ffi_ssl_ctx_set_cert(void *cdata_ctx, void *cdata_cert,
    u_char *err, size_t *err_len)
{
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
    int                 num;
    size_t              n;
    u_long              e;

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


int
ngx_http_lua_ffi_ssl_ctx_set_ciphers(void *cdata_ctx, const char *cipher,
    unsigned char *err, size_t *err_len)
{
    SSL_CTX            *ssl_ctx = cdata_ctx;

    size_t              n;
    u_long              e;
    const char         *default_err;

    if (!SSL_CTX_set_cipher_list(ssl_ctx, cipher)) {
        default_err = "SSL_CTX_set_cipher_list() failed";
        goto failed;
    }

    return NGX_OK;

failed:

    e = ERR_get_error();
    n = ngx_strlen(default_err);
    *err_len = ngx_http_lua_ssl_get_error(e, err, *err_len, default_err, n);

    return NGX_ERROR;
}


int
ngx_http_lua_ffi_ssl_ctx_set_crl(void *cdata_ctx, const u_char *crl,
    size_t size, unsigned char *err, size_t *err_len)
{
    BIO         *bio = NULL;
    SSL_CTX     *ssl_ctx = cdata_ctx;

    size_t       n;
    u_long       e;
    X509_CRL    *x509_crl;
    X509_STORE  *x509_store;
    const char  *default_err;

    x509_store = SSL_CTX_get_cert_store(ssl_ctx);
    if (x509_store == NULL) {
        default_err = "ca cert store is empty";
        goto failed;
    }

    bio = BIO_new_mem_buf(crl, size);
    if (bio == NULL) {
        default_err = "BIO_new_mem_buf() failed";
        goto failed;
    }

    for (;;) {
        x509_crl = PEM_read_bio_X509_CRL(bio, NULL, NULL, NULL);
        if (x509_crl == NULL) {
            n = ERR_peek_last_error();

            if (ERR_GET_LIB(n) == ERR_LIB_PEM
                && ERR_GET_REASON(n) == PEM_R_NO_START_LINE)
            {
                ERR_clear_error();
                break;
            }

            default_err = "PEM_read_bio_X509_CRL() failed";
            goto failed;
        }

        if (!X509_STORE_add_crl(x509_store, x509_crl)) {
            X509_CRL_free(x509_crl);
            default_err = "X509_STORE_add_crl() failed";
            goto failed;
        }

        X509_CRL_free(x509_crl);
    }

    X509_STORE_set_flags(x509_store,
                         X509_V_FLAG_CRL_CHECK | X509_V_FLAG_CRL_CHECK_ALL);

    BIO_free_all(bio);

    return NGX_OK;

failed:

    if (bio != NULL) {
        BIO_free_all(bio);
    }

    e = ERR_get_error();
    n = ngx_strlen(default_err);
    *err_len = ngx_http_lua_ssl_get_error(e, err, *err_len, default_err, n);

    return NGX_ERROR;
}


void
ngx_http_lua_ffi_ssl_ctx_free(void *cdata)
{
    SSL_CTX    *ssl_ctx = cdata;

    X509_STORE *x509_store;

    x509_store = SSL_CTX_get_cert_store(ssl_ctx);
    if (x509_store != NULL) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "lua ssl ctx x509 store reference: %p:%d", x509_store,
                       x509_store->references);
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log,
                   0, "lua ssl ctx free: %p:%d", ssl_ctx, ssl_ctx->references);

    SSL_CTX_free(ssl_ctx);
}


X509_STORE *
ngx_http_lua_ffi_ssl_x509_store_init(unsigned char *err, size_t *err_len)
{
    size_t       n;
    u_long       e;
    X509_STORE  *x509_store;
    const char  *default_err;

    x509_store = X509_STORE_new();
    if (x509_store == NULL) {
        default_err = "X509_STORE_new() failed";
        goto failed;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua ssl x509 store init: %p:%d", x509_store,
                   x509_store->references);

    return x509_store;

failed:

    e = ERR_get_error();
    n = ngx_strlen(default_err);
    *err_len = ngx_http_lua_ssl_get_error(e, err, *err_len, default_err, n);

    return NULL;
}


int
ngx_http_lua_ffi_ssl_x509_store_add_cert(void *cdata_store, const u_char *cert,
    size_t size, unsigned char *err, size_t *err_len)
{
    BIO         *bio = NULL;
    X509_STORE  *x509_store = cdata_store;

    X509        *x509;
    size_t       n;
    u_long       e;
    const char  *default_err;

    bio = BIO_new_mem_buf(cert, size);
    if (bio == NULL) {
        default_err = "BIO_new_mem_buf() failed";
        goto failed;
    }

    for (;;) {
        x509 = PEM_read_bio_X509(bio, NULL, NULL, NULL);
        if (x509 == NULL) {
            n = ERR_peek_last_error();

            if (ERR_GET_LIB(n) == ERR_LIB_PEM
                && ERR_GET_REASON(n) == PEM_R_NO_START_LINE)
            {
                /* end of file */
                ERR_clear_error();
                break;
            }

            default_err = "PEM_read_bio_X509() failed";
            goto failed;
        }

        if (!X509_STORE_add_cert(x509_store, x509)) {
            X509_free(x509);
            default_err = "X509_STORE_add_cert() failed";
            goto failed;
        }

        X509_free(x509);
    }

    BIO_free_all(bio);

    return NGX_OK;

failed:

    if(bio != NULL) {
        BIO_free_all(bio);
    }

    e = ERR_get_error();
    n = ngx_strlen(default_err);
    *err_len = ngx_http_lua_ssl_get_error(e, err, *err_len, default_err, n);

    return NGX_ERROR;
}


void
ngx_http_lua_ffi_ssl_x509_store_free(void *cdata_store)
{
    X509_STORE      *x509_store = cdata_store;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua ssl x509 store free: %p:%d", x509_store,
                   x509_store->references);

    X509_STORE_free(x509_store);
}


#endif /* NGX_LUA_NO_FFI_API */


#endif /* NGX_HTTP_SSL */
