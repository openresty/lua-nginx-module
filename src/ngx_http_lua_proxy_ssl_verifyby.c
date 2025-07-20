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
#include "ngx_http_lua_proxy_ssl_verifyby.h"
#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_ssl.h"


static void ngx_http_lua_proxy_ssl_verify_done(void *data);
static void ngx_http_lua_proxy_ssl_verify_aborted(void *data);
static u_char *ngx_http_lua_log_proxy_ssl_verify_error(ngx_log_t *log,
    u_char *buf, size_t len);
static ngx_int_t ngx_http_lua_proxy_ssl_verify_by_chunk(lua_State *L,
    ngx_http_request_t *r);


ngx_int_t
ngx_http_lua_proxy_ssl_verify_set_callback(ngx_conf_t *cf)
{

#ifdef LIBRESSL_VERSION_NUMBER

    ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                  "LibreSSL does not support by proxy_ssl_verify_by_lua*");

    return NGX_ERROR;

#else

    ngx_flag_t           proxy_pass_ssl = 0;
    ngx_pool_cleanup_t  *cln;
    ngx_ssl_t           *ssl;
    void                *plcf;

    /*
     * Nginx doesn't export ngx_http_proxy_loc_conf_t, so we can't directly
     * get plcf here, and we also don't want to change ngx_http_proxy_module's
     * code organization, since that it means to add a header file to Nginx.
     * I know it's a bit clumsy here, anyway the solution is good enough
     */
    for (cln = cf->pool->cleanup; cln; cln = cln->next) {
        if (cln->handler != ngx_ssl_cleanup_ctx) {
            continue;
        }

        ssl = cln->data;

        plcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_proxy_module);
        if (plcf == ngx_ssl_get_server_conf(ssl->ctx)) {
            /* here we make sure that ssl is plcf->upstream.ssl */
            proxy_pass_ssl = 1;

            break;
        }
    }

    if (!proxy_pass_ssl) {
        ngx_log_error(NGX_LOG_EMERG, cf->log, 0, "proxy_ssl_verify_by_lua* "
                      "should be used with proxy_pass https url");

        return NGX_ERROR;
    }

#if (!defined SSL_ERROR_WANT_RETRY_VERIFY \
     || OPENSSL_VERSION_NUMBER < 0x30000020L)

    ngx_log_error(NGX_LOG_EMERG, cf->log, 0, "OpenSSL too old to support "
                  "proxy_ssl_verify_by_lua*");

    return NGX_ERROR;

#else

    SSL_CTX_set_cert_verify_callback(ssl->ctx,
                                     ngx_http_lua_proxy_ssl_verify_handler,
                                     NULL);
    return NGX_OK;

#endif

#endif
}


ngx_int_t
ngx_http_lua_proxy_ssl_verify_handler_file(ngx_http_request_t *r,
    ngx_http_lua_loc_conf_t *llcf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadfile(r->connection->log, L,
                                     llcf->proxy_ssl_verify_src.data,
                                     &llcf->proxy_ssl_verify_src_ref,
                                     llcf->proxy_ssl_verify_src_key);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_proxy_ssl_verify_by_chunk(L, r);
}


ngx_int_t
ngx_http_lua_proxy_ssl_verify_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_loc_conf_t *llcf, lua_State *L)
{
    ngx_int_t           rc;

    rc = ngx_http_lua_cache_loadbuffer(r->connection->log, L,
                                       llcf->proxy_ssl_verify_src.data,
                                       llcf->proxy_ssl_verify_src.len,
                                       &llcf->proxy_ssl_verify_src_ref,
                                       llcf->proxy_ssl_verify_src_key,
                           (const char *) llcf->proxy_ssl_verify_chunkname);
    if (rc != NGX_OK) {
        return rc;
    }

    /*  make sure we have a valid code chunk */
    ngx_http_lua_assert(lua_isfunction(L, -1));

    return ngx_http_lua_proxy_ssl_verify_by_chunk(L, r);
}


char *
ngx_http_lua_proxy_ssl_verify_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_proxy_ssl_verify_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_proxy_ssl_verify_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
#if (!defined SSL_ERROR_WANT_RETRY_VERIFY \
     || OPENSSL_VERSION_NUMBER < 0x30000020L)

    /* SSL_set_retry_verify() was added in OpenSSL 3.0.2 */
    ngx_log_error(NGX_LOG_EMERG, cf->log, 0,
                  "at least OpenSSL 3.0.2 required but found "
                  OPENSSL_VERSION_TEXT);

    return NGX_CONF_ERROR;

#else

    size_t                       chunkname_len;
    u_char                      *chunkname;
    u_char                      *cache_key = NULL;
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    /*  must specify a concrete handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->proxy_ssl_verify_handler) {
        return "is duplicate";
    }

    if (ngx_http_lua_ssl_init(cf->log) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    value = cf->args->elts;

    llcf->proxy_ssl_verify_handler =
        (ngx_http_lua_loc_conf_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_proxy_ssl_verify_handler_file) {
        /* Lua code in an external file */

        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        cache_key = ngx_http_lua_gen_file_cache_key(cf, value[1].data,
                                                    value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        llcf->proxy_ssl_verify_src.data = name;
        llcf->proxy_ssl_verify_src.len = ngx_strlen(name);

    } else {
        cache_key = ngx_http_lua_gen_chunk_cache_key(cf,
                                                     "proxy_ssl_verify_by_lua",
                                                     value[1].data,
                                                     value[1].len);
        if (cache_key == NULL) {
            return NGX_CONF_ERROR;
        }

        chunkname = ngx_http_lua_gen_chunk_name(cf, "proxy_ssl_verify_by_lua",
                                          sizeof("proxy_ssl_verify_by_lua") - 1,
                                          &chunkname_len);
        if (chunkname == NULL) {
            return NGX_CONF_ERROR;
        }

        /* Don't eval nginx variables for inline lua code */
        llcf->proxy_ssl_verify_src = value[1];
        llcf->proxy_ssl_verify_chunkname = chunkname;
    }

    llcf->proxy_ssl_verify_src_key = cache_key;

    return NGX_CONF_OK;

#endif  /* SSL_ERROR_WANT_RETRY_VERIFY */
}


int
ngx_http_lua_proxy_ssl_verify_handler(X509_STORE_CTX *x509_store, void *arg)
{
    lua_State                       *L;
    ngx_int_t                        rc;
    ngx_connection_t                *c, *fc;
    ngx_http_request_t              *r = NULL, *fr = NULL;
    ngx_pool_cleanup_t              *cln;
    ngx_http_core_loc_conf_t        *clcf;
    ngx_http_lua_loc_conf_t         *llcf;
    ngx_http_lua_ssl_ctx_t          *cctx;
    ngx_http_core_srv_conf_t        *cscf;
    ngx_ssl_conn_t                  *ssl_conn;

    ssl_conn = X509_STORE_CTX_get_ex_data(x509_store,
                                          SSL_get_ex_data_X509_STORE_CTX_idx());

    c = ngx_ssl_get_connection(ssl_conn);  /* connection to upstream */

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "proxy ssl verify: connection reusable: %ud", c->reusable);

    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);

    dd("proxy ssl verify handler, cert-verify-ctx=%p", cctx);

    if (cctx && cctx->entered_proxy_ssl_verify_handler) {
        /* not the first time */

        if (cctx->done) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                           "proxy_ssl_verify_by_lua: "
                           "cert verify callback exit code: %d",
                           cctx->exit_code);

            dd("lua proxy ssl verify done, finally");
            return cctx->exit_code;
        }

        return SSL_set_retry_verify(ssl_conn);
    }

    dd("first time");

#if (nginx_version < 1017009)
    ngx_reusable_connection(c, 0);
#endif

    r = c->data;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
    if (llcf->upstream_skip_openssl_default_verify == 0) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "proxy_ssl_verify_by_lua: openssl default verify");

        rc = X509_verify_cert(x509_store);
        if (rc == 0) {
            return 0;  /* verify failure or error */
        }
    }

    fc = ngx_http_lua_create_fake_connection(NULL);
    if (fc == NULL) {
        goto failed;
    }

    fc->log->handler = ngx_http_lua_log_proxy_ssl_verify_error;
    fc->log->data = fc;

    fc->addr_text = c->addr_text;
    fc->listening = c->listening;

    fr = ngx_http_lua_create_fake_request(fc);
    if (fr == NULL) {
        goto failed;
    }

    cscf = ngx_http_get_module_srv_conf(r, ngx_http_core_module);
    fr->main_conf = cscf->ctx->main_conf;
    fr->srv_conf = cscf->ctx->srv_conf;
    /*
     * the hook is running after find config phase, and r->loc_conf may
     * already been changed, we need to get correct location configs
     */
    fr->loc_conf = r->loc_conf;

    fc->log->file = c->log->file;
    fc->log->log_level = c->log->log_level;
    fc->ssl = c->ssl;

    clcf = ngx_http_get_module_loc_conf(fr, ngx_http_core_module);

#if nginx_version >= 1009000
    ngx_set_connection_log(fc, clcf->error_log);
#else
    ngx_http_set_connection_log(fc, clcf->error_log);
#endif

    if (cctx == NULL) {
        cctx = ngx_pcalloc(c->pool, sizeof(ngx_http_lua_ssl_ctx_t));
        if (cctx == NULL) {
            goto failed;  /* error */
        }

        cctx->ctx_ref = LUA_NOREF;
    }

    cctx->exit_code = 1;  /* successful by default */
    cctx->x509_store = x509_store;
    cctx->connection = c;
    cctx->request = fr;
    cctx->entered_proxy_ssl_verify_handler = 1;
    cctx->done = 0;

    dd("setting cctx");

    if (SSL_set_ex_data(c->ssl->connection, ngx_http_lua_ssl_ctx_index, cctx)
        == 0)
    {
        ngx_ssl_error(NGX_LOG_ALERT, c->log, 0, "SSL_set_ex_data() failed");
        goto failed;
    }

    llcf = ngx_http_get_module_loc_conf(fr, ngx_http_lua_module);

    /* TODO honor lua_code_cache off */
    L = ngx_http_lua_get_lua_vm(fr, NULL);

    c->log->action = "loading proxy ssl verify by lua";

    if (llcf->proxy_ssl_verify_handler == NULL) {
        ngx_log_error(NGX_LOG_ALERT, c->log, 0,
                      "no proxy_ssl_verify_by_lua* defined in "
                      "server %V", &cscf->server_name);

        goto failed;
    }

    rc = llcf->proxy_ssl_verify_handler(fr, llcf, L);

    if (rc >= NGX_OK || rc == NGX_ERROR) {
        cctx->done = 1;

        if (cctx->cleanup) {
            *cctx->cleanup = NULL;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, c->log, 0,
                       "proxy_ssl_verify_by_lua: handler return value: %i, "
                       "cert verify callback exit code: %d", rc, cctx->exit_code);

        c->log->action = "proxy pass SSL handshaking";
        return cctx->exit_code;
    }

    /* rc == NGX_DONE */

    cln = ngx_pool_cleanup_add(fc->pool, 0);
    if (cln == NULL) {
        goto failed;
    }

    cln->handler = ngx_http_lua_proxy_ssl_verify_done;
    cln->data = cctx;

    if (cctx->cleanup == NULL) {
        cln = ngx_pool_cleanup_add(c->pool, 0);
        if (cln == NULL) {
            goto failed;
        }

        cln->data = cctx;
        cctx->cleanup = &cln->handler;
    }

    *cctx->cleanup = ngx_http_lua_proxy_ssl_verify_aborted;

    return SSL_set_retry_verify(ssl_conn);

failed:

    if (fr && fr->pool) {
        ngx_http_lua_free_fake_request(fr);
    }

    if (fc) {
        ngx_http_lua_close_fake_connection(fc);
    }

    return 0;  /* verify failure or error */
}


static void
ngx_http_lua_proxy_ssl_verify_done(void *data)
{
    ngx_connection_t        *c;
    ngx_http_lua_ssl_ctx_t  *cctx = data;

    dd("lua proxy ssl verify done");

    if (cctx->aborted) {
        return;
    }

    ngx_http_lua_assert(cctx->done == 0);

    cctx->done = 1;

    if (cctx->cleanup) {
        *cctx->cleanup = NULL;
    }

    c = cctx->connection;

    c->log->action = "proxy pass SSL handshaking";

    ngx_post_event(c->write, &ngx_posted_events);
}


static void
ngx_http_lua_proxy_ssl_verify_aborted(void *data)
{
    ngx_http_lua_ssl_ctx_t  *cctx = data;

    dd("lua proxy ssl verify aborted");

    if (cctx->done) {
        /* completed successfully already */
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, cctx->connection->log, 0,
                   "proxy_ssl_verify_by_lua: cert verify callback aborted");

    cctx->aborted = 1;
    cctx->request->connection->ssl = NULL;

    ngx_http_lua_finalize_fake_request(cctx->request, NGX_ERROR);
}


static u_char *
ngx_http_lua_log_proxy_ssl_verify_error(ngx_log_t *log,
    u_char *buf, size_t len)
{
    u_char              *p;
    ngx_connection_t    *c;

    if (log->action) {
        p = ngx_snprintf(buf, len, " while %s", log->action);
        len -= p - buf;
        buf = p;
    }

    p = ngx_snprintf(buf, len, ", context: proxy_ssl_verify_by_lua*");
    len -= p - buf;
    buf = p;

    c = log->data;

    if (c && c->addr_text.len) {
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
ngx_http_lua_proxy_ssl_verify_by_chunk(lua_State *L, ngx_http_request_t *r)
{
    int                      co_ref;
    ngx_int_t                rc;
    lua_State               *co;
    ngx_http_lua_ctx_t      *ctx;
    ngx_pool_cleanup_t      *cln;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        ctx = ngx_http_lua_create_ctx(r);
        if (ctx == NULL) {
            rc = NGX_ERROR;
            ngx_http_lua_finalize_request(r, rc);
            return rc;
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

        rc = NGX_ERROR;
        ngx_http_lua_finalize_request(r, rc);
        return rc;
    }

    /*  move code closure to new coroutine */
    lua_xmove(L, co, 1);

#ifndef OPENRESTY_LUAJIT
    /*  set closure's env table to new coroutine's globals table */
    ngx_http_lua_get_globals_table(co);
    lua_setfenv(co, -2);
#endif

    /* save nginx request in coroutine globals table */
    ngx_http_lua_set_req(co, r);

    ctx->cur_co_ctx = &ctx->entry_co_ctx;
    ctx->cur_co_ctx->co = co;
    ctx->cur_co_ctx->co_ref = co_ref;
#ifdef NGX_LUA_USE_ASSERT
    ctx->cur_co_ctx->co_top = 1;
#endif

    ngx_http_lua_attach_co_ctx_to_L(co, ctx->cur_co_ctx);

    /* register request cleanup hooks */
    if (ctx->cleanup == NULL) {
        cln = ngx_pool_cleanup_add(r->pool, 0);
        if (cln == NULL) {
            rc = NGX_ERROR;
            ngx_http_lua_finalize_request(r, rc);
            return rc;
        }

        cln->handler = ngx_http_lua_request_cleanup_handler;
        cln->data = ctx;
        ctx->cleanup = &cln->handler;
    }

    ctx->context = NGX_HTTP_LUA_CONTEXT_PROXY_SSL_VERIFY;

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


/*
 * openssl's doc of SSL_CTX_set_cert_verify_callback:
 * In any case a viable verification result value must
 * be reflected in the error member of x509_store_ctx,
 * which can be done using X509_STORE_CTX_set_error.
 */
int
ngx_http_lua_ffi_ssl_set_verify_result(ngx_http_request_t *r,
    int verify_result, char **err)
{
#ifdef SSL_ERROR_WANT_RETRY_VERIFY
    ngx_ssl_conn_t                  *ssl_conn;
    ngx_connection_t                *c;
    ngx_http_lua_ssl_ctx_t          *cctx;
    X509_STORE_CTX                  *x509_store;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    dd("get cctx session");

    c = ngx_ssl_get_connection(ssl_conn);

    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);
    if (cctx == NULL) {
        *err = "bad lua context";
        return NGX_ERROR;
    }

    x509_store = cctx->x509_store;

    X509_STORE_CTX_set_error(x509_store, verify_result);

    return NGX_OK;
#else
    *err = "OpenSSL too old to support this function";

    return NGX_ERROR;
#endif
}


int
ngx_http_lua_ffi_ssl_get_verify_result(ngx_http_request_t *r, char **err)
{
#ifdef SSL_ERROR_WANT_RETRY_VERIFY
    ngx_ssl_conn_t                  *ssl_conn;
    ngx_connection_t                *c;
    ngx_http_lua_ssl_ctx_t          *cctx;
    X509_STORE_CTX                  *x509_store;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NGX_ERROR;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NGX_ERROR;
    }

    dd("get cctx session");

    c = ngx_ssl_get_connection(ssl_conn);

    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);
    if (cctx == NULL) {
        *err = "bad lua context";
        return NGX_ERROR;
    }

    x509_store = cctx->x509_store;

    return X509_STORE_CTX_get_error(x509_store);
#else
    *err = "OpenSSL too old to support this function";

    return NGX_ERROR;
#endif
}


void *
ngx_http_lua_ffi_ssl_get_verify_cert(ngx_http_request_t *r, char **err)
{
#ifdef SSL_ERROR_WANT_RETRY_VERIFY
    ngx_ssl_conn_t                  *ssl_conn;
    ngx_connection_t                *c;
    ngx_http_lua_ssl_ctx_t          *cctx;
    X509_STORE_CTX                  *x509_store;
    X509                            *x509;

    if (r->connection == NULL || r->connection->ssl == NULL) {
        *err = "bad request";
        return NULL;
    }

    ssl_conn = r->connection->ssl->connection;
    if (ssl_conn == NULL) {
        *err = "bad ssl conn";
        return NULL;
    }

    dd("get cctx session");

    c = ngx_ssl_get_connection(ssl_conn);

    cctx = ngx_http_lua_ssl_get_ctx(c->ssl->connection);
    if (cctx == NULL) {
        *err = "bad lua context";
        return NULL;
    }

    x509_store = cctx->x509_store;

    x509 = X509_STORE_CTX_get0_cert(x509_store);

    return x509;
#else
    *err = "OpenSSL too old to support this function";

    return NULL;
#endif
}

#endif /* NGX_HTTP_SSL */
