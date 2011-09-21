#ifndef NGX_HTTP_LUA_CONTROL_H
#define NGX_HTTP_LUA_CONTROL_H


#include "ngx_http_lua_common.h"


int ngx_http_lua_ngx_exec(lua_State *L);
int ngx_http_lua_ngx_redirect(lua_State *L);
int ngx_http_lua_ngx_exit(lua_State *L);


#endif /* NGX_HTTP_LUA_CONTROL_H */

