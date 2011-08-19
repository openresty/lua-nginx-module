#ifndef NGX_HTTP_LUA_CTX_H
#define NGX_HTTP_LUA_CTX_H


#include "ngx_http_lua_common.h"


int ngx_http_lua_ngx_get_ctx(lua_State *L);
int ngx_http_lua_ngx_set_ctx(lua_State *L);


#endif /* NGX_HTTP_LUA_CTX_H */

