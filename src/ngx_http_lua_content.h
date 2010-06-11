#ifndef NGX_HTTP_LUA_CONTENT_H__
#define NGX_HTTP_LUA_CONTENT_H__

#include "ngx_http_lua_common.h"

extern ngx_int_t ngx_http_lua_content_by_chunk(
		lua_State *l,
		ngx_http_request_t *r
		);

#endif

// vi:ts=4 sw=4 fdm=marker

