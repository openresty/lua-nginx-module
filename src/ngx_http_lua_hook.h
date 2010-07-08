#ifndef NGX_HTTP_LUA_HOOK_H
#define NGX_HTTP_LUA_HOOK_H

#include "ngx_http_lua_common.h"


jmp_buf ngx_http_lua_exception;

int ngx_http_lua_atpanic(lua_State *L);
int ngx_http_lua_print(lua_State *L);

int ngx_http_lua_ngx_send_headers(lua_State *L);

int ngx_http_lua_ngx_say(lua_State *L);
int ngx_http_lua_ngx_print(lua_State *L);

int ngx_http_lua_ngx_flush(lua_State *L);
int ngx_http_lua_ngx_eof(lua_State *L);

int ngx_http_lua_ngx_location_capture(lua_State *L);


#endif /* NGX_HTTP_LUA_HOOK_H */

