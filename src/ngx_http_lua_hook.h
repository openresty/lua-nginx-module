#ifndef NGX_HTTP_LUA_HOOK_H__
#define NGX_HTTP_LUA_HOOK_H__

#include "ngx_http_lua_common.h"

extern jmp_buf ngx_http_lua_exception;

extern int ngx_http_lua_atpanic(lua_State *l);
extern int ngx_http_lua_print(lua_State *l);
extern int ngx_http_lua_ngx_send_headers(lua_State *l);
extern int ngx_http_lua_ngx_echo(lua_State *l);
extern int ngx_http_lua_ngx_flush(lua_State *l);
extern int ngx_http_lua_ngx_eof(lua_State *l);

#endif

// vi:ts=4 sw=4 fdm=marker

