
/*
 * Copyright (C) Yichun Zhang (agentzh)
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
#include "ngx_http_lua_sslcertby.h"


static void ngx_http_lua_ssl_cert_done(void *data);
static void ngx_http_lua_ssl_cert_aborted(void *data);
static u_char *ngx_http_lua_log_ssl_cert_error(ngx_log_t *log, u_char *buf,
    size_t len);
static ngx_int_t ngx_http_lua_ssl_cert_by_chunk(lua_State *L,
    ngx_http_request_t *r);


ngx_int_t
ngx_http_lua_ssl_cert_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadfile(r, L, lscf->ssl_cert_src.data,
                                     lscf->ssl_cert_src_key);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_ssl_cert_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_ssl_cert_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadbuffer(r, L, lscf->ssl_cert_src.data,
                                       lscf->ssl_cert_src.len,
                                       lscf->ssl_cert_src_key,
                                       "=ssl_certificate_by_lua");
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_ssl_cert_by_chunk(L, r);
}


char *
ngx_http_lua_ssl_cert_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                      *p;
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_srv_conf_t    *lscf = conf;

    dd("enter");

    /*  must specifiy a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lscf->ssl_cert_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    lscf->ssl_cert_handler = (ngx_http_lua_srv_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_ssl_cert_handler_file) {
        /* Lua code in an external file */

        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->ssl_cert_src.data = name;
        lscf->ssl_cert_src.len = ngx_strlen(name);

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_FILE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->ssl_cert_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_FILE_TAG, NGX_HTTP_LUA_FILE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';

    } else {
        /* inlined Lua code */

        lscf->ssl_cert_src = value[1];

        p = ngx_palloc(cf->pool, NGX_HTTP_LUA_INLINE_KEY_LEN + 1);
        if (p == NULL) {
            return NGX_CONF_ERROR;
        }

        lscf->ssl_cert_src_key = p;

        p = ngx_copy(p, NGX_HTTP_LUA_INLINE_TAG, NGX_HTTP_LUA_INLINE_TAG_LEN);
        p = ngx_http_lua_digest_hex(p, value[1].data, value[1].len);
        *p = '\0';
    }

    return NGX_CONF_OK;
}


int
ngx_http_lua_ssl_cert_handler(ngx_ssl_conn_t *ssl_conn, void *data)
{
    lua_State                       *L;
    ngx_int_t                        rc;
    ngx_connection_t                *c, *fc;
    ngx_http_request_t              *r = NULL;
    ngx_pool_cleanup_t              *cln;
    ngx_http_connection_t           *hc;
    ngx_http_lua_srv_conf_t         *lscf;
    ngx_http_lua_ssl_cert_ctx_t     *cctx;

    c = ngx_ssl_get_connection(ssl_conn);

    dd("c = %p", c);

    cctx = c->ssl->lua_ctx;

    dd("ssl cert handler, cert-ctx=%p", cctx);

    if (cctx) {
        /* not the first time */

        if (cctx->done) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                           "lua_certificate_by_lua: cert cb exit code: %d",
                           cctx->exit_code);

            dd("lua ssl cert done, finally");
            return cctx->exit_code;
        }

        return -1;
    }

    /* cctx == NULL */

    dd("first time");

    hc = c->data;

    fc = ngx_http_lua_create_fake_connection(NULL);
    if (fc == NULL) {
        goto failed;
    }

    fc->log->handler = ngx_http_lua_log_ssl_cert_error;
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

    cctx = ngx_pcalloc(c->pool, sizeof(ngx_http_lua_ssl_cert_ctx_t));
    if (cctx == NULL) {
        goto failed;  /* error */
    }

    cctx->exit_code = 1;  /* successful by default */
    cctx->connection = c;
    cctx->request = r;

    dd("setting cctx");

    c->ssl->lua_ctx = cctx;

    lscf = ngx_http_get_module_srv_conf(r, ngx_http_lua_module);

    /* TODO honor lua_code_cache off */
    L = ngx_http_lua_get_lua_vm(r, NULL);

    c->log->action = "loading SSL certificate by lua";

    rc = lscf->ssl_cert_handler(r, lscf, L);

    if (rc >= NGX_OK || rc == NGX_ERROR) {
        cctx->done = 1;

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "lua_certificate_by_lua: handler return value: %i, "
                       "cert cb exit code: %d", rc, cctx->exit_code);

        c->log->action = "SSL handshaking";
        return cctx->exit_code;
    }

    /* rc == NGX_DONE */

    cln = ngx_pool_cleanup_add(fc->pool, 0);
    if (cln == NULL) {
        goto failed;
    }

    cln->handler = ngx_http_lua_ssl_cert_done;
    cln->data = cctx;

    cln = ngx_pool_cleanup_add(c->pool, 0);
    if (cln == NULL) {
        goto failed;
    }

    cln->handler = ngx_http_lua_ssl_cert_aborted;
    cln->data = cctx;

    return -1;

#if 1
failed:

    if (r && r->pool) {
        ngx_http_lua_free_fake_request(r);
    }

    if (fc) {
        ngx_http_lua_close_fake_connection(fc);
    }

    return 0;
#endif
}


static void
ngx_http_lua_ssl_cert_done(void *data)
{
    ngx_connection_t                *c;
    ngx_http_lua_ssl_cert_ctx_t     *cctx = data;

    dd("lua ssl cert done");

    if (cctx->aborted) {
        return;
    }

    ngx_http_lua_assert(cctx->done == 0);

    cctx->done = 1;

    c = cctx->connection;

    c->log->action = "SSL handshaking";

    ngx_post_event(c->write, &ngx_posted_events);
}


static void
ngx_http_lua_ssl_cert_aborted(void *data)
{
    ngx_http_lua_ssl_cert_ctx_t     *cctx = data;

    dd("lua ssl cert done");

    if (cctx->done) {
        /* completed successfully already */
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cctx->connection->log, 0,
                   "lua_certificate_by_lua: cert cb aborted");

    cctx->aborted = 1;
    cctx->request->connection->ssl = NULL;

    ngx_http_lua_finalize_fake_request(cctx->request, NGX_ERROR);
}


static u_char *
ngx_http_lua_log_ssl_cert_error(ngx_log_t *log, u_char *buf, size_t len)
{
    u_char              *p;
    ngx_connection_t    *c;

    if (log->action) {
        p = ngx_snprintf(buf, len, " while %s", log->action);
        len -= p - buf;
        buf = p;
    }

    p = ngx_snprintf(buf, len, ", context: ssl_certificate_by_lua*");
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
ngx_http_lua_ssl_cert_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    int                      co_ref;
    ngx_int_t                rc;
    lua_State               *co;
    ngx_http_lua_ctx_t      *ctx;
    ngx_http_cleanup_t      *cln;

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

    /*  {{{ new coroutine to handle request */
    co = ngx_http_lua_new_thread(r, L, &co_ref);

    if (co == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                     "lua: failed to create new coroutine to handle request");

        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /*  move code closure to new coroutine */
    lua_xmove(L, co, 1);

    /*  set closure's env table to new coroutine's globals table */
    ngx_http_lua_get_globals_table(co);
    lua_setfenv(co, -2);

    /* save nginx request in coroutine globals table */
    ngx_http_lua_set_req(co, r);

    ctx->cur_co_ctx = &ctx->entry_co_ctx;
    ctx->cur_co_ctx->co = co;
    ctx->cur_co_ctx->co_ref = co_ref;
#ifdef NGX_LUA_USE_ASSERT
    ctx->cur_co_ctx->co_top = 1;
#endif

    /* register request cleanup hooks */
    if (ctx->cleanup == NULL) {
        cln = ngx_http_cleanup_add(r, 0);
        if (cln == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        cln->handler = ngx_http_lua_request_cleanup_handler;
        cln->data = ctx;
        ctx->cleanup = &cln->handler;
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_SSL_CERT;

    rc = ngx_http_lua_run_thread(L, r, ctx, 0);

    if (rc == NGX_ERROR || rc >= NGX_OK) {
        /* do nothing */

    } else if (rc == NGX_AGAIN) {
        rc = ngx_http_lua_content_run_posted_threads(L, r, ctx, 0);

    } else if (rc == NGX_DONE) {
        rc = ngx_http_lua_content_run_posted_threads(L, r, ctx, 1);

    } else {
        rc = NGX_OK;
    }

    ngx_http_lua_finalize_request(r, rc);
    return rc;
}


#ifndef NGX_LUA_NO_FFI_API

int
ngx_http_lua_ffi_ssl_get_tls1_version(ngx_http_request_t *r, char **err)
{
    ngx_ssl_conn_t    *ssl_conn;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    dd("tls1 ver: %d", (int) TLS1_get_version(ssl_conn));

    return (int) TLS1_get_version(ssl_conn);
}


int
ngx_http_lua_ffi_ssl_clear_certs(ngx_http_request_t *r, char **err)
{
    ngx_ssl_conn_t    *ssl_conn;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    SSL_certs_clear(ssl_conn);
    return NGX_OK;
}


int
ngx_http_lua_ffi_ssl_set_der_certificate(ngx_http_request_t *r,
    const char *data, size_t len, char **err)
{
    BIO               *bio = NULL;
    X509              *x509 = NULL;
    ngx_ssl_conn_t    *ssl_conn;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    bio = BIO_new_mem_buf((char *) data, len);
    if (bio == NULL) {
       *err = " BIO_new_mem_buf() failed";
        goto failed;
    }

    x509 = d2i_X509_bio(bio, NULL);
    if (x509 == NULL) {
        *err = " d2i_X509_bio() failed";
        goto failed;
    }

    if (SSL_use_certificate(ssl_conn, x509) == 0) {
        *err = " SSL_use_certificate() failed";
        goto failed;
    }

#if 0
    if (SSL_set_ex_data(ssl_conn, ngx_ssl_certificate_index, x509) == 0) {
        *err = " SSL_set_ex_data() failed";
        goto failed;
    }
#endif

    X509_free(x509);
    x509 = NULL;

    /* read rest of the chain */

    while (!BIO_eof(bio)) {

        x509 = d2i_X509_bio(bio, NULL);
        if (x509 == NULL) {
            *err = "d2i_X509_bio() failed";
            goto failed;
        }

        if (SSL_add0_chain_cert(ssl_conn, x509) == 0) {
            *err = "SSL_add0_chain_cert() failed";
            goto failed;
        }
    }

    BIO_free(bio);

    *err = NULL;
    return NGX_OK;

failed:

    if (bio) {
        BIO_free(bio);
    }

    if (x509) {
        X509_free(x509);
    }

    return NGX_ERROR;
}


int
ngx_http_lua_ffi_ssl_set_der_private_key(ngx_http_request_t *r,
    const char *data, size_t len, char **err)
{
    BIO               *bio = NULL;
    EVP_PKEY          *pkey = NULL;
    ngx_ssl_conn_t    *ssl_conn;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    bio = BIO_new_mem_buf((char *) data, len);
    if (bio == NULL) {
        *err = "BIO_new_mem_buf() failed";
        goto failed;
    }

    pkey = d2i_PrivateKey_bio(bio, NULL);
    if (pkey == NULL) {
        *err = "d2i_PrivateKey_bio() failed";
        goto failed;
    }

    if (SSL_use_PrivateKey(ssl_conn, pkey) == 0) {
        *err = "SSL_CTX_use_PrivateKey() failed";
        goto failed;
    }

    EVP_PKEY_free(pkey);
    BIO_free(bio);

    return NGX_OK;

failed:

    if (pkey) {
        EVP_PKEY_free(pkey);
    }

    if (bio) {
        BIO_free(bio);
    }

    return NGX_ERROR;
}


int
ngx_http_lua_ffi_ssl_raw_server_addr(ngx_http_request_t *r, char **addr,
    size_t *addrlen, int *addrtype, char **err)
{
#if (NGX_HAVE_UNIX_DOMAIN)
    struct sockaddr_un   *saun;
#endif
    ngx_ssl_conn_t       *ssl_conn;
    ngx_connection_t     *c;
    struct sockaddr_in   *sin;
#if (NGX_HAVE_INET6)
    struct sockaddr_in6  *sin6;
#endif

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    c = ngx_ssl_get_connection(ssl_conn);

    if (ngx_connection_local_sockaddr(c, NULL, 0) != NGX_OK) {
        return 0;
    }

    switch (c->local_sockaddr->sa_family) {

#if (NGX_HAVE_INET6)
    case AF_INET6:
        sin6 = (struct sockaddr_in6 *) c->local_sockaddr;
        *addrlen = 16;
        *addr = (char *) &sin6->sin6_addr.s6_addr;
        *addrtype = AF_INET6;

        break;
#endif

#if (NGX_HAVE_UNIX_DOMAIN)
    case AF_UNIX:
        saun = (struct sockaddr_un *) c->local_sockaddr;

        /* on Linux sockaddr might not include sun_path at all */
        if (c->local_socklen <=
                         (socklen_t) offsetof(struct sockaddr_un, sun_path))
        {
            *addr = "";
            *addrlen = 0;

        } else {
            *addr = saun->sun_path;
            *addrlen = ngx_strlen(saun->sun_path);
        }

        *addrtype = AF_UNIX;
        break;
#endif

    default: /* AF_INET */
        sin = (struct sockaddr_in *) c->local_sockaddr;
        *addr = (char *) &sin->sin_addr.s_addr;
        *addrlen = 4;
        *addrtype = AF_INET;
        break;
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_ssl_server_name(ngx_http_request_t *r, char **name,
    size_t *namelen, char **err)
{
    ngx_ssl_conn_t          *ssl_conn;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    *name = (char *) SSL_get_servername(ssl_conn, TLSEXT_NAMETYPE_host_name);

    if (*name) {
        *namelen = ngx_strlen(*name);
        return NGX_OK;
    }

    return NGX_DECLINED;
}


int
ngx_http_lua_ffi_cert_pem_to_der(const u_char *pem, size_t pem_len, u_char *der,
    char **err)
{
    int       total, len;
    BIO      *bio;
    X509     *x509;
    u_long    n;

    bio = BIO_new_mem_buf((char *) pem, (int) pem_len);
    if (bio == NULL) {
        *err = "BIO_new_mem_buf() failed";
        return NGX_ERROR;
    }

    x509 = PEM_read_bio_X509_AUX(bio, NULL, NULL, NULL);
    if (x509 == NULL) {
        *err = "PEM_read_bio_X509_AUX() failed";
        return NGX_ERROR;
    }

    total = i2d_X509(x509, &der);
    if (total < 0) {
        X509_free(x509);
        BIO_free(bio);
        return NGX_ERROR;
    }

    X509_free(x509);

    /* read rest of the chain */

    for ( ;; ) {

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

            /* some real error */

            *err = "PEM_read_bio_X509() failed";
            BIO_free(bio);
            return NGX_ERROR;
        }

        len = i2d_X509(x509, &der);
        if (len < 0) {
            *err = "i2d_X509() failed";
            X509_free(x509);
            BIO_free(bio);
            return NGX_ERROR;
        }

        total += len;

        X509_free(x509);
    }

    BIO_free(bio);

    return total;
}


int
ngx_http_lua_ffi_ssl_get_ocsp_responder_from_der_chain(
    const char *chain_data, size_t chain_len, unsigned char *out,
    size_t *out_size, char **err)
{
    int                        rc = NGX_OK;
    BIO                       *bio = NULL;
    char                      *s;
    X509                      *cert = NULL, *issuer = NULL;
    size_t                     len;
    STACK_OF(OPENSSL_STRING)  *aia = NULL;

    /* certificate */

    bio = BIO_new_mem_buf((char *) chain_data, chain_len);
    if (bio == NULL) {
        *err = "BIO_new_mem_buf() failed";
        rc = NGX_ERROR;
        goto done;
    }

    cert = d2i_X509_bio(bio, NULL);
    if (cert == NULL) {
        *err = "d2i_X509_bio() failed";
        rc = NGX_ERROR;
        goto done;
    }

    /* responder */

    aia = X509_get1_ocsp(cert);
    if (aia == NULL) {
        rc = NGX_DECLINED;
        goto done;
    }

    s = sk_OPENSSL_STRING_value(aia, 0);
    if (s == NULL) {
        rc = NGX_DECLINED;
        goto done;
    }

    len = ngx_strlen(s);
    if (len > *out_size) {
        len = *out_size;
        rc = NGX_BUSY;

    } else {
        rc = NGX_OK;
        *out_size = len;
    }

    ngx_memcpy(out, s, len);

    X509_email_free(aia);
    aia = NULL;

    /* issuer */

    if (BIO_eof(bio)) {
        *err = "no issuer certificate in chain";
        rc = NGX_ERROR;
        goto done;
    }

    issuer = d2i_X509_bio(bio, NULL);
    if (issuer == NULL) {
        *err = "d2i_X509_bio() failed";
        rc = NGX_ERROR;
        goto done;
    }

    if (X509_check_issued(issuer, cert) != X509_V_OK) {
        *err = "issuer certificate not next to leaf";
        rc = NGX_ERROR;
        goto done;
    }

    X509_free(issuer);
    X509_free(cert);
    BIO_free(bio);

    return rc;

done:

    if (aia) {
        X509_email_free(aia);
    }

    if (issuer) {
        X509_free(issuer);
    }

    if (cert) {
        X509_free(cert);
    }

    if (bio) {
        BIO_free(bio);
    }

    return rc;
}


int
ngx_http_lua_ffi_ssl_create_ocsp_request(const char *chain_data,
    size_t chain_len, unsigned char *out, size_t *out_size, char **err)
{
    int                        rc = NGX_ERROR;
    BIO                       *bio = NULL;
    X509                      *cert = NULL, *issuer = NULL;
    size_t                     len;
    OCSP_CERTID               *id;
    OCSP_REQUEST              *ocsp = NULL;

    /* certificate */

    bio = BIO_new_mem_buf((char *) chain_data, chain_len);
    if (bio == NULL) {
        *err = "BIO_new_mem_buf() failed";
        goto failed;
    }

    cert = d2i_X509_bio(bio, NULL);
    if (cert == NULL) {
        *err = "d2i_X509_bio() failed";
        goto failed;
    }

    if (BIO_eof(bio)) {
        *err = "no issuer certificate in chain";
        goto failed;
    }

    issuer = d2i_X509_bio(bio, NULL);
    if (issuer == NULL) {
        *err = "d2i_X509_bio() failed";
        goto failed;
    }

    ocsp = OCSP_REQUEST_new();
    if (ocsp == NULL) {
        *err = "OCSP_REQUEST_new() failed";
        goto failed;
    }

    id = OCSP_cert_to_id(NULL, cert, issuer);
    if (id == NULL) {
        *err = "OCSP_cert_to_id() failed";
        goto failed;
    }

    if (OCSP_request_add0_id(ocsp, id) == NULL) {
        *err = "OCSP_request_add0_id() failed";
        goto failed;
    }

    len = i2d_OCSP_REQUEST(ocsp, NULL);
    if (len <= 0) {
        *err = "i2d_OCSP_REQUEST() failed";
        goto failed;
    }

    if (len > *out_size) {
        *err = "output buffer too small";
        *out_size = len;
        rc = NGX_BUSY;
        goto failed;
    }

    len = i2d_OCSP_REQUEST(ocsp, &out);
    if (len <=  0) {
        *err = "i2d_OCSP_REQUEST() failed";
        goto failed;
    }

    *out_size = len;

    OCSP_REQUEST_free(ocsp);
    X509_free(issuer);
    X509_free(cert);
    BIO_free(bio);

    return NGX_OK;

failed:

    if (ocsp) {
        OCSP_REQUEST_free(ocsp);
    }

    if (issuer) {
        X509_free(issuer);
    }

    if (cert) {
        X509_free(cert);
    }

    if (bio) {
        BIO_free(bio);
    }

    return rc;
}


int
ngx_http_lua_ffi_ssl_validate_ocsp_response(const u_char *resp,
    size_t resp_len, const char *chain_data, size_t chain_len,
    u_char *errbuf, size_t *errbuf_size)
{
    int                    n;
    BIO                   *bio = NULL;
    X509                  *cert = NULL, *issuer = NULL;
    OCSP_CERTID           *id = NULL;
    OCSP_RESPONSE         *ocsp = NULL;
    OCSP_BASICRESP        *basic = NULL;
    STACK_OF(X509)        *chain = NULL;
    ASN1_GENERALIZEDTIME  *thisupdate, *nextupdate;

    ocsp = d2i_OCSP_RESPONSE(NULL, &resp, resp_len);
    if (ocsp == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "d2i_OCSP_RESPONSE() failed") - errbuf;
        goto error;
    }

    n = OCSP_response_status(ocsp);

    if (n != OCSP_RESPONSE_STATUS_SUCCESSFUL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "OCSP response not successful (%d: %s)",
                                    n, OCSP_response_status_str(n)) - errbuf;
        goto error;
    }

    basic = OCSP_response_get1_basic(ocsp);
    if (basic == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "OCSP_response_get1_basic() failed")
                       - errbuf;
        goto error;
    }

    /* get issuer certificate from chain */

    bio = BIO_new_mem_buf((char *) chain_data, chain_len);
    if (bio == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "BIO_new_mem_buf() failed")
                       - errbuf;
        goto error;
    }

    cert = d2i_X509_bio(bio, NULL);
    if (cert == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "d2i_X509_bio() failed")
                       - errbuf;
        goto error;
    }

    if (BIO_eof(bio)) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "no issuer certificate in chain")
                       - errbuf;
        goto error;
    }

    issuer = d2i_X509_bio(bio, NULL);
    if (issuer == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "d2i_X509_bio() failed") - errbuf;
        goto error;
    }

    chain = sk_X509_new_null();
    if (chain == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "sk_X509_new_null() failed") - errbuf;
        goto error;
    }

    (void) sk_X509_push(chain, issuer);

    if (OCSP_basic_verify(basic, chain, NULL, OCSP_NOVERIFY) != 1) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "OCSP_basic_verify() failed") - errbuf;
        goto error;
    }

    id = OCSP_cert_to_id(NULL, cert, issuer);
    if (id == NULL) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "OCSP_cert_to_id() failed") - errbuf;
        goto error;
    }

    if (OCSP_resp_find_status(basic, id, &n, NULL, NULL,
                              &thisupdate, &nextupdate)
        != 1)
    {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "certificate status not found in the "
                                    "OCSP response") - errbuf;
        goto error;
    }

    if (n != V_OCSP_CERTSTATUS_GOOD) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "certificate status \"%s\" in the OCSP "
                                    "response", OCSP_cert_status_str(n))
                       - errbuf;
        goto error;
    }

    if (OCSP_check_validity(thisupdate, nextupdate, 300, -1) != 1) {
        *errbuf_size = ngx_snprintf(errbuf, *errbuf_size,
                                    "OCSP_check_validity() failed") - errbuf;
        goto error;
    }

    sk_X509_free(chain);
    X509_free(cert);
    X509_free(issuer);
    BIO_free(bio);
    OCSP_CERTID_free(id);
    OCSP_BASICRESP_free(basic);
    OCSP_RESPONSE_free(ocsp);

    return NGX_OK;

error:

    if (chain) {
        sk_X509_free(chain);
    }

    if (id) {
        OCSP_CERTID_free(id);
    }

    if (basic) {
        OCSP_BASICRESP_free(basic);
    }

    if (ocsp) {
        OCSP_RESPONSE_free(ocsp);
    }

    if (cert) {
        X509_free(cert);
    }

    if (issuer) {
        X509_free(issuer);
    }

    if (bio) {
        BIO_free(bio);
    }

    ERR_clear_error();

    return NGX_ERROR;
}


static int
ngx_http_lua_ssl_empty_status_callback(ngx_ssl_conn_t *ssl_conn, void *data)
{
    return SSL_TLSEXT_ERR_OK;
}


int
ngx_http_lua_ffi_ssl_set_ocsp_status_resp(ngx_http_request_t *r,
    const u_char *resp, size_t resp_len, char **err)
{
    u_char                  *p;
    SSL_CTX                 *ctx;
    ngx_ssl_conn_t          *ssl_conn;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    if (ssl_conn->tlsext_status_type == -1) {
        dd("no ocsp status req from client");
        return NGX_DECLINED;
    }

    /* we have to register an empty status callback here otherwise
     * OpenSSL won't send the response staple. */

    ctx = SSL_get_SSL_CTX(ssl_conn);
    SSL_CTX_set_tlsext_status_cb(ctx,
                                 ngx_http_lua_ssl_empty_status_callback);

    p = OPENSSL_malloc(resp_len);
    if (p == NULL) {
        *err = "OPENSSL_malloc() failed";
        return NGX_ERROR;
    }

    ngx_memcpy(p, resp, resp_len);

    dd("set ocsp resp: resp_len=%d", (int) resp_len);
    (void) SSL_set_tlsext_status_ocsp_resp(ssl_conn, p, resp_len);
    ssl_conn->tlsext_status_expected = 1;

    return NGX_OK;
}

#endif  /* NGX_LUA_NO_FFI_API */


#endif /* NGX_HTTP_SSL */
