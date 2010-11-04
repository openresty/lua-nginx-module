/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#include "ngx_http_lua_filter.h"
#include "ngx_http_lua_util.h"

ngx_http_output_header_filter_pt ngx_http_lua_next_header_filter;
ngx_http_output_body_filter_pt ngx_http_lua_next_body_filter;

static ngx_int_t ngx_http_lua_header_filter(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_body_filter(ngx_http_request_t *r, ngx_chain_t *in);
static ngx_int_t ngx_http_lua_rewrite_phase_handler(ngx_http_request_t *r);
static void ngx_http_lua_post_read(ngx_http_request_t *r);

ngx_int_t
ngx_http_lua_filter_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt         *h;
    ngx_http_core_main_conf_t   *cmcf;

    /* setting up rewrite phase handler to force reading request body */
    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);
    h = ngx_array_push(&cmcf->phases[NGX_HTTP_REWRITE_PHASE].handlers);

    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_lua_rewrite_phase_handler;

    /* setting up output filters to intercept subrequest responses */
    ngx_http_lua_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_lua_header_filter;

    ngx_http_lua_next_body_filter = ngx_http_top_body_filter;
    ngx_http_top_body_filter = ngx_http_lua_body_filter;

    return NGX_OK;
}

static ngx_int_t
ngx_http_lua_header_filter(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t *ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx && ctx->capture) {
        /* force subrequest response body buffer in memory */
        r->filter_need_in_memory = 1;

        return NGX_OK;
    }

    return ngx_http_lua_next_header_filter(r);
}

static ngx_int_t
ngx_http_lua_body_filter(ngx_http_request_t *r, ngx_chain_t *in)
{
    int rc;
    ngx_http_lua_ctx_t *ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (!ctx || !ctx->capture) {
        return ngx_http_lua_next_body_filter(r, in);
    }

    rc = ngx_http_lua_add_copy_chain(r->pool,
            &ctx->body, in);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    ngx_http_lua_discard_bufs(r->pool, in);

    return NGX_OK;
}

static ngx_int_t
ngx_http_lua_rewrite_phase_handler(ngx_http_request_t *r)
{
    ngx_http_lua_loc_conf_t *llcf;
    ngx_http_lua_ctx_t      *ctx;
    ngx_int_t               rc;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (!llcf->force_read_body) {
        dd("no need to reading request body");
        return NGX_DECLINED;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx != NULL) {
        if (ctx->read_body_done) {
            dd("request body has been read");
            return NGX_DECLINED;
        }
        return NGX_AGAIN;
    }

    if (r->method != NGX_HTTP_POST && r->method != NGX_HTTP_PUT) {
        dd("request method should not have a body: %d", (int) r->method);
        return NGX_DECLINED;
    }

    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_ctx_t));

    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_http_set_ctx(r, ctx, ngx_http_lua_module);

    dd("start to read request body");

    rc = ngx_http_read_client_request_body(r, ngx_http_lua_post_read);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return rc;
    }

    if (rc == NGX_AGAIN) {
        ctx->waiting_more_body = 1;
        return NGX_AGAIN;
    }

    return NGX_DECLINED;
}

static void
ngx_http_lua_post_read(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t  *ctx;

    r->read_event_handler = ngx_http_request_empty_handler;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    ctx->read_body_done = 1;

#if defined(nginx_version) && nginx_version >= 8011
    r->main->count--;
#endif

    if (ctx->waiting_more_body) {
        ctx->waiting_more_body = 0;
        ngx_http_core_run_phases(r);
    }
}

