/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef NGX_HTTP_LUA_COROUTINE_H
#define NGX_HTTP_LUA_COROUTINE_H


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_coroutine_api(ngx_log_t *log, lua_State *L);


#endif /* NGX_HTTP_LUA_COROUTINE_H */

