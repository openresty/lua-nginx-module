#ifndef NGX_HTTP_LUA_UTIL_H__
#define NGX_HTTP_LUA_UTIL_H__

#include "ngx_http_lua_common.h"

// FIXME: find a way to store Lua state into module config context!
extern lua_State* ngx_http_lua_vm;

extern lua_State* ngx_http_lua_newstate();
extern ngx_int_t ngx_http_lua_set_by_chunk(
        lua_State *l,
        ngx_http_request_t *r,
        ngx_str_t *val,
        ngx_http_variable_value_t *args,
        size_t nargs
        );

extern ngx_int_t ngx_http_lua_has_inline_var(ngx_str_t *s);

#endif

