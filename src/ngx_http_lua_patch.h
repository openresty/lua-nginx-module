#ifndef NGX_HTTP_LUA_PATCH_H
#define NGX_HTTP_LUA_PATCH_H


#include "ngx_http_lua_common.h"


void ngx_http_lua_pcre_malloc_init(ngx_pool_t *pool);
void ngx_http_lua_pcre_malloc_done();


#endif /* NGX_HTTP_LUA_PATCH_H */
/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

