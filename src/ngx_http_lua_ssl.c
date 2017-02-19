
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#if (NGX_HTTP_SSL)


#define ngx_http_lua_ssl_check_method(method, method_len, s)             \
    (method_len == sizeof(s) - 1                                         \
    && ngx_strncmp((method), (s), method_len) == 0)


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


static ngx_int_t
ngx_http_lua_ssl_ctx_create_method(const SSL_METHOD **ssl_method,
    const u_char *method, size_t method_len, char **err)
{
    if (ngx_http_lua_ssl_check_method(method, method_len,
                                      "SSLv23_method"))
    {
        *ssl_method = SSLv23_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "SSLv2_method"))
    {
        *err = "SSLv2 methods disabled";
        return NGX_ERROR;

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "SSLv2_server_method"))
    {
        *err = "SSLv2 methods disabled";
        return NGX_ERROR;

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "SSLv2_client_method"))
    {
        *err = "SSLv2 methods disabled";
        return NGX_ERROR;

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "SSLv3_method"))
    {
        *err = "SSLv3 methods disabled";
        return NGX_ERROR;

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "SSLv3_server_method"))
    {
        *err = "SSLv3 methods disabled";
        return NGX_ERROR;

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "SSLv3_client_method"))
    {
        *err = "SSLv3 methods disabled";
        return NGX_ERROR;

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "SSLv23_server_method"))
    {
        *ssl_method = SSLv23_server_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "SSLv23_client_method"))
    {
        *ssl_method = SSLv23_client_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "TLSv1_method"))
    {
        *ssl_method = TLSv1_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "TLSv1_server_method"))
    {
        *ssl_method = TLSv1_server_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "TLSv1_client_method"))
    {
        *ssl_method = TLSv1_client_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "TLSv1_1_method"))
    {
        *ssl_method = TLSv1_1_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "TLSv1_1_server_method"))
    {
        *ssl_method = TLSv1_1_server_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "TLSv1_1_client_method"))
    {
        *ssl_method = TLSv1_1_client_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "TLSv1_2_method"))
    {
        *ssl_method = TLSv1_2_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "TLSv1_2_server_method"))
    {
        *ssl_method = TLSv1_2_server_method();

    } else if (ngx_http_lua_ssl_check_method(method, method_len,
                                             "TLSv1_2_client_method"))
    {
        *ssl_method = TLSv1_2_client_method();

    } else {
        *err = "Unknown method";
        return NGX_ERROR;
    }

    return NGX_OK;
}


static void
ngx_http_lua_ssl_info_callback(const ngx_ssl_conn_t *ssl_conn,
    int where, int ret)
{
    BIO               *rbio, *wbio;
    ngx_connection_t  *c;

    if (where & SSL_CB_HANDSHAKE_START) {
        c = ngx_ssl_get_connection((ngx_ssl_conn_t *) ssl_conn);

        if (c->ssl->handshaked) {
            c->ssl->renegotiation = 1;
            ngx_log_debug0(NGX_LOG_DEBUG_EVENT, c->log, 0, "SSL renegotiation");
        }
    }

    if ((where & SSL_CB_ACCEPT_LOOP) == SSL_CB_ACCEPT_LOOP) {
        c = ngx_ssl_get_connection((ngx_ssl_conn_t *) ssl_conn);

        if (!c->ssl->handshake_buffer_set) {
            /*
             * By default OpenSSL uses 4k buffer during a handshake,
             * which is too low for long certificate chains and might
             * result in extra round-trips.
             *
             * To adjust a buffer size we detect that buffering was added
             * to write side of the connection by comparing rbio and wbio.
             * If they are different, we assume that it's due to buffering
             * added to wbio, and set buffer size.
             */

            rbio = SSL_get_rbio((ngx_ssl_conn_t *) ssl_conn);
            wbio = SSL_get_wbio((ngx_ssl_conn_t *) ssl_conn);

            if (rbio != wbio) {
                (void) BIO_set_write_buffer_size(wbio, NGX_SSL_BUFSIZE);
                c->ssl->handshake_buffer_set = 1;
            }
        }
    }
}


static void
ngx_http_lua_ssl_ctx_set_default_options(SSL_CTX *ctx)
{
    /* {{{copy nginx ssl secure options */

#ifdef SSL_OP_MICROSOFT_SESS_ID_BUG
    SSL_CTX_set_options(ctx, SSL_OP_MICROSOFT_SESS_ID_BUG);
#endif

#ifdef SSL_OP_NETSCAPE_CHALLENGE_BUG
    SSL_CTX_set_options(ctx, SSL_OP_NETSCAPE_CHALLENGE_BUG);
#endif

#ifdef SSL_OP_SSLREF2_REUSE_CERT_TYPE_BUG
    SSL_CTX_set_options(ctx, SSL_OP_SSLREF2_REUSE_CERT_TYPE_BUG);
#endif

#ifdef SSL_OP_MICROSOFT_BIG_SSLV3_BUFFER
    SSL_CTX_set_options(ctx, SSL_OP_MICROSOFT_BIG_SSLV3_BUFFER);
#endif

#ifdef SSL_OP_MSIE_SSLV2_RSA_PADDING
    /* this option allow a potential SSL 2.0 rollback (CAN-2005-2969) */
    SSL_CTX_set_options(ctx, SSL_OP_MSIE_SSLV2_RSA_PADDING);
#endif

#ifdef SSL_OP_SSLEAY_080_CLIENT_DH_BUG
    SSL_CTX_set_options(ctx, SSL_OP_SSLEAY_080_CLIENT_DH_BUG);
#endif

#ifdef SSL_OP_TLS_D5_BUG
    SSL_CTX_set_options(ctx, SSL_OP_TLS_D5_BUG);
#endif

#ifdef SSL_OP_TLS_BLOCK_PADDING_BUG
    SSL_CTX_set_options(ctx, SSL_OP_TLS_BLOCK_PADDING_BUG);
#endif

#ifdef SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS
    SSL_CTX_set_options(ctx, SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS);
#endif

    SSL_CTX_set_options(ctx, SSL_OP_SINGLE_DH_USE);

#ifdef SSL_CTRL_CLEAR_OPTIONS
    /* only in 0.9.8m+ */
    SSL_CTX_clear_options(ctx,
                          SSL_OP_NO_SSLv2|SSL_OP_NO_SSLv3|SSL_OP_NO_TLSv1);
#endif

#ifdef SSL_OP_NO_TLSv1_1
    SSL_CTX_clear_options(ctx, SSL_OP_NO_TLSv1_1);
#endif

#ifdef SSL_OP_NO_TLSv1_2
    SSL_CTX_clear_options(ctx, SSL_OP_NO_TLSv1_2);
#endif

#ifdef SSL_OP_NO_COMPRESSION
    SSL_CTX_set_options(ctx, SSL_OP_NO_COMPRESSION);
#endif

#ifdef SSL_MODE_RELEASE_BUFFERS
    SSL_CTX_set_mode(ctx, SSL_MODE_RELEASE_BUFFERS);
#endif

#ifdef SSL_MODE_NO_AUTO_CHAIN
    SSL_CTX_set_mode(ctx, SSL_MODE_NO_AUTO_CHAIN);
#endif
    /* }}} */

    /* Disable SSLv2 in the case when method == SSLv23_method() and the
     * cipher list contains SSLv2 ciphers (not the default, should be rare)
     * The bundled OpenSSL doesn't have SSLv2 support but the system OpenSSL may
     * SSLv3 is disabled because it's susceptible to downgrade attacks
     */

    SSL_CTX_set_options(ctx, SSL_OP_NO_SSLv2);
    SSL_CTX_set_options(ctx, SSL_OP_NO_SSLv3);

    /* read as many input bytes as possible (for non-blocking reads) */
    SSL_CTX_set_read_ahead(ctx, 1);

    SSL_CTX_set_info_callback(ctx, ngx_http_lua_ssl_info_callback);
}


void *
ngx_http_lua_ffi_ssl_ctx_init(const u_char *method,
    size_t method_len, char **err)
{
    const SSL_METHOD        *ssl_method;
    SSL_CTX                 *ssl_ctx;

    if (ngx_http_lua_ssl_ctx_create_method(&ssl_method,
                                           method,
                                           method_len,
                                           err) != NGX_OK)
    {
        return NULL;
    }

    ssl_ctx = SSL_CTX_new(ssl_method);
    if (ssl_ctx == NULL) {
        *err = "SSL_CTX_new() failed";
        ngx_ssl_error(NGX_LOG_ERR, ngx_cycle->log, 0, *err);
        return NULL;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "lua ssl ctx init: %p:%d", ssl_ctx, ssl_ctx->references);

    ngx_http_lua_ssl_ctx_set_default_options(ssl_ctx);

    return ssl_ctx;
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

    if (!SSL_CTX_use_PrivateKey(ssl_ctx, key)) {
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
                   0,
                   "lua ssl ctx free: %p:%d",
                   ssl_ctx,
                   ssl_ctx->references);

    SSL_CTX_free(ssl_ctx);
}


#endif /* NGX_LUA_NO_FFI_API */


#endif /* NGX_HTTP_SSL */
