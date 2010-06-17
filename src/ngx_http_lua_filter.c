#include "ngx_http_lua_filter.h"

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
	return ngx_http_lua_next_header_filter(r);
}

static ngx_int_t
ngx_http_lua_body_filter(ngx_http_request_t *r, ngx_chain_t *in)
{
	return ngx_http_lua_next_body_filter(r, in);
}

// vi:ts=4 sw=4 fdm=marker

