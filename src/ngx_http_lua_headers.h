#ifndef NGX_HTTP_LUA_HEADERS_H
#define NGX_HTTP_LUA_HEADERS_H


#include "ngx_http_lua_common.h"


int ngx_http_lua_ngx_send_headers(lua_State *L);
int ngx_http_lua_ngx_req_get_headers(lua_State *L);
int ngx_http_lua_ngx_req_header_clear(lua_State *L);
int ngx_http_lua_ngx_req_header_set(lua_State *L);

int ngx_http_lua_ngx_header_get(lua_State *L);
int ngx_http_lua_ngx_header_set(lua_State *L);


#endif /* NGX_HTTP_LUA_HEADERS_H */

