/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#ifndef NGX_HTTP_LUA_CACHE_H
#define NGX_HTTP_LUA_CACHE_H

#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_cache_loadbuffer(lua_State *L, const u_char *buf,
        int buf_len, const char *name, char **err);
ngx_int_t ngx_http_lua_cache_loadfile(lua_State *L, const char *script,
        char **err);


#endif /* NGX_HTTP_LUA_CACHE_H */

