#ifndef NGX_HTTP_LUA_ECHO_H
#define NGX_HTTP_LUA_ECHO_H


#include "ngx_http_lua_common.h"


int ngx_http_lua_ngx_say(lua_State *L);
int ngx_http_lua_ngx_print(lua_State *L);
int ngx_http_lua_ngx_flush(lua_State *L);
int ngx_http_lua_ngx_eof(lua_State *L);


#endif /* NGX_HTTP_LUA_ECHO_H */

