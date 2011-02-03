/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#ifndef NGX_HTTP_LUA_CONF_H__
#define NGX_HTTP_LUA_CONF_H__

#include "ngx_http_lua_common.h"

extern void* ngx_http_lua_create_main_conf(ngx_conf_t *cf);
extern char* ngx_http_lua_init_main_conf(ngx_conf_t *cf, void *conf);

extern void* ngx_http_lua_create_loc_conf(ngx_conf_t *cf);
extern char* ngx_http_lua_merge_loc_conf(ngx_conf_t *cf, void *parent,
        void *child);

#endif
