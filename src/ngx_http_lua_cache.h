#ifndef NGX_HTTP_LUA_CACHE_H__
#define NGX_HTTP_LUA_CACHE_H__

#include "ngx_http_lua_common.h"

extern ngx_int_t ngx_http_lua_cache_loadbuffer(
        lua_State *l,
        const u_char *buf,
        int buf_len,
        const char *name
        );
extern ngx_int_t ngx_http_lua_cache_loadfile(
        lua_State *l,
        const char *script
        );

#endif

// vi:ts=4 sw=4 fdm=marker

