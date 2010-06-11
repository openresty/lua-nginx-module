#ifndef NGX_HTTP_LUA_CONF_H__
#define NGX_HTTP_LUA_CONF_H__

#include "ngx_http_lua_common.h"

typedef struct {
	lua_State *lua;
} ngx_http_lua_main_conf_t;

typedef struct {
	ngx_str_t src;	// content_by_lua inline script / script file path
} ngx_http_lua_loc_conf_t;

extern void* ngx_http_lua_create_main_conf(ngx_conf_t *cf);
extern char* ngx_http_lua_init_main_conf(ngx_conf_t *cf, void *conf);

extern void* ngx_http_lua_create_loc_conf(ngx_conf_t *cf);
extern char* ngx_http_lua_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child);

#endif

// vi:ts=4 sw=4 fdm=marker

