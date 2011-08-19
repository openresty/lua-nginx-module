#ifndef NGX_HTTP_LUA_LOG_H
#define NGX_HTTP_LUA_LOG_H


#include "ngx_http_lua_common.h"


int ngx_http_lua_print(lua_State *L);
int ngx_http_lua_ngx_log(lua_State *L);


#endif /* NGX_HTTP_LUA_LOG_H */

