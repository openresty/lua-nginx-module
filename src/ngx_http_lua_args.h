#ifndef NGX_HTTP_LUA_ARGS
#define NGX_HTTP_LUA_ARGS


#include "ngx_http_lua_common.h"


int ngx_http_lua_ngx_req_get_uri_args(lua_State *L);
int ngx_http_lua_ngx_req_get_post_args(lua_State *L);


#endif /* NGX_HTTP_LUA_ARGS */

