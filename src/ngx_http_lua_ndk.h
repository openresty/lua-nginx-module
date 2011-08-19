#ifndef NGX_HTTP_LUA_NDK_H
#define NGX_HTTP_LUA_NDK_H


#include "ngx_http_lua_common.h"


#if defined(NDK) && NDK
int ngx_http_lua_ndk_set_var_get(lua_State *L);
int ngx_http_lua_ndk_set_var_set(lua_State *L);
int ngx_http_lua_run_set_var_directive(lua_State *L);
#endif


#endif /* NGX_HTTP_LUA_NDK_H */

