#ifndef NGX_HTTP_LUA_TIME_H
#define NGX_HTTP_LUA_TIME_H


#include "ngx_http_lua_common.h"


int ngx_http_lua_ngx_today(lua_State *L);
int ngx_http_lua_ngx_time(lua_State *L);
int ngx_http_lua_ngx_localtime(lua_State *L);
int ngx_http_lua_ngx_utctime(lua_State *L);
int ngx_http_lua_ngx_cookie_time(lua_State *L);
int ngx_http_lua_ngx_http_time(lua_State *L);
int ngx_http_lua_ngx_parse_http_time(lua_State *L);


#endif /* NGX_HTTP_LUA_TIME_H */

