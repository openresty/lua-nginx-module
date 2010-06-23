#include "ngx_http_lua_filter.h"
#include "ngx_http_lua_util.h"

ngx_http_output_header_filter_pt ngx_http_lua_next_header_filter;
ngx_http_output_body_filter_pt ngx_http_lua_next_body_filter;

static ngx_int_t ngx_http_lua_header_filter(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_body_filter(ngx_http_request_t *r, ngx_chain_t *in);

ngx_int_t
ngx_http_lua_filter_init(ngx_conf_t *cf)
{
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

	if(ctx && ctx->capture) {
		// force subrequest response body buffer in memory
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

	if(!ctx || !ctx->capture) {
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

// vi:ts=4 sw=4 fdm=marker

