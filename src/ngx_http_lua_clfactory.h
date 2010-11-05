/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#ifndef NGX_HTTP_LUA_CLFACTORY_H__
#define NGX_HTTP_LUA_CLFACTORY_H__

#include "ngx_http_lua_common.h"

#define CLFACTORY_BEGIN_CODE "return function() "
#define CLFACTORY_BEGIN_SIZE (sizeof(CLFACTORY_BEGIN_CODE)-1)

#define CLFACTORY_END_CODE " end"
#define CLFACTORY_END_SIZE (sizeof(CLFACTORY_END_CODE)-1)

extern int ngx_http_lua_clfactory_loadfile(lua_State *l, const char *filename);
extern int ngx_http_lua_clfactory_loadstring(lua_State *l, const char *s);
extern int ngx_http_lua_clfactory_loadbuffer(lua_State *l, const char *buff, size_t size, const char *name);

#endif

