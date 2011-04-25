#ifndef NGX_HTTP_LUA_PATCH_H__
#define NGX_HTTP_LUA_PATCH_H__

#include "ngx_http_lua_common.h"

extern void ngx_http_lua_pcre_malloc_init(ngx_pool_t *pool);
extern void ngx_http_lua_pcre_malloc_done();

#endif
/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

