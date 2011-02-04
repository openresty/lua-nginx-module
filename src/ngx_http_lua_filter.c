/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#define DDEBUG 0

#include "ngx_http_lua_filter.h"
#include "ngx_http_lua_util.h"


ngx_http_output_header_filter_pt ngx_http_lua_next_header_filter;
ngx_http_output_body_filter_pt ngx_http_lua_next_body_filter;


static ngx_int_t ngx_http_lua_header_filter(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_body_filter(ngx_http_request_t *r,
        ngx_chain_t *in);


ngx_int_t
ngx_http_lua_filter_init(ngx_conf_t *cf)
{
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
    int                              rc;
    ngx_http_lua_ctx_t              *ctx;
    ngx_http_lua_ctx_t              *pr_ctx;

    dd("in body filter");

    if (in == NULL) {
        return ngx_http_lua_next_body_filter(r, NULL);
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (! ctx || ! ctx->capture) {
        dd("no ctx or no capture %.*s", (int) r->uri.len, r->uri.data);

        return ngx_http_lua_next_body_filter(r, in);
    }

    if (ctx->run_post_subrequest) {
        return NGX_OK;
    }

    if (r->parent == NULL) {
        return NGX_ERROR;
    }

    pr_ctx = ngx_http_get_module_ctx(r->parent, ngx_http_lua_module);
    if (pr_ctx == NULL) {
        return NGX_ERROR;
    }

    rc = ngx_http_lua_add_copy_chain(r, pr_ctx, &ctx->body, in);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    ngx_http_lua_discard_bufs(r->pool, in);

    return ngx_http_lua_flush_postponed_outputs(r);
}

