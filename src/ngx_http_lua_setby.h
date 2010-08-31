#ifndef NGX_HTTP_LUA_SET_BY_H__
#define NGX_HTTP_LUA_SET_BY_H__

#include "ngx_http_lua_common.h"

extern ngx_int_t ngx_http_lua_set_by_chunk(
		lua_State *l,
		ngx_http_request_t *r,
		ngx_str_t *val,
		ngx_http_variable_value_t *args,
		size_t nargs,
        ngx_str_t data
		);

#endif

// vi:ts=4 sw=4 fdm=marker

