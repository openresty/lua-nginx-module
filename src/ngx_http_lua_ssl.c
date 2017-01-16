
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


int
ngx_http_lua_ssl_password_callback(char *buf, int size, int rwflag,
    void *userdata)
{
    ngx_str_t *pwd = userdata;

    if (rwflag) {
        ngx_log_error(NGX_LOG_ALERT, ngx_cycle->log, 0,
                      "ngx_ssl_password_callback() is called for encryption");
        return 0;
    }

    if (pwd->len == 0) {
        return 0;
    }

    if (pwd->len > (size_t) size) {
        ngx_log_error(NGX_LOG_ERR, ngx_cycle->log, 0,
                      "password is truncated to %d bytes", size);
    } else {
        size = pwd->len;
    }

    ngx_memcpy(buf, pwd->data, size);

    return size;
}


ngx_int_t
ngx_http_lua_ssl_certificate(ngx_ssl_t *ssl, ngx_str_t *cert,
    ngx_str_t *priv_key, ngx_str_t *password, ngx_log_t *log)
{
    BIO                     *cbio = NULL;
    BIO                     *pbio = NULL;
    X509                    *x509 = NULL;
    EVP_PKEY                *pkey = NULL;
    ngx_int_t                rc = NGX_ERROR;

    cbio = BIO_new_mem_buf((char *)cert->data, cert->len);
    if (cbio == NULL) {
        ngx_ssl_error(NGX_LOG_ERR, log, 0, "BIO_new_mem_buf() failed");
        goto done;
    }

    /*
    * Reading the PEM-formatted certificate from memory into an X509
    */

    x509 = PEM_read_bio_X509(cbio, NULL, 0, NULL);
    if (x509 == NULL) {
        ngx_ssl_error(NGX_LOG_ERR, log, 0, "PEM_read_bio_X509() failed");
        goto done;
    }

    if (!SSL_CTX_use_certificate(ssl->ctx, x509)) {
        ngx_ssl_error(NGX_LOG_ERR, log, 0, "SSL_CTX_use_certificate() failed");
        goto done;
    }

    pbio = BIO_new_mem_buf((char *)priv_key->data, priv_key->len);
    if (pbio == NULL) {
        ngx_ssl_error(NGX_LOG_ERR, log, 0, "BIO_new_mem_buf() failed");
        goto done;
    }

    pkey = PEM_read_bio_PrivateKey(pbio, NULL,
                                   ngx_http_lua_ssl_password_callback,
                                   (void *)password);
    if (pkey == NULL) {
        ngx_ssl_error(NGX_LOG_ERR, log, 0, "PEM_read_bio_PrivateKey() failed");
        goto done;
    }

    if (!SSL_CTX_use_PrivateKey(ssl->ctx, pkey)) {
        ngx_ssl_error(NGX_LOG_ERR, log, 0, "SSL_CTX_use_PrivateKey() failed");
        goto done;
    }

    rc = NGX_OK;

done:

    if (pkey) {
        EVP_PKEY_free(pkey);
    }

    if (x509) {
        X509_free(x509);
    }

    if (pbio) {
        BIO_free(pbio);
    }

    if (cbio) {
        BIO_free(cbio);
    }

    if (rc == NGX_ERROR) {
        ERR_clear_error();
    }

    SSL_CTX_set_default_passwd_cb(ssl->ctx, NULL);

    return rc;
}

#endif /* NGX_HTTP_SSL */
