/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#ifndef NGX_HTTP_LUA_CONTENT_BY_H__
#define NGX_HTTP_LUA_CONTENT_BY_H__

#include "ngx_http_lua_common.h"

extern ngx_int_t ngx_http_lua_content_by_chunk(
        lua_State *l,
        ngx_http_request_t *r
        );
extern void ngx_http_lua_wev_handler(ngx_http_request_t *r);

#endif


