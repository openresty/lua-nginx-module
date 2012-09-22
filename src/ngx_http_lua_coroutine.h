/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef NGX_HTTP_LUA_COROUTINE_H
#define NGX_HTTP_LUA_COROUTINE_H


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_coroutine_api(ngx_log_t *log, lua_State *L);

int ngx_http_lua_coroutine_create_helper(lua_State *L, ngx_http_request_t **pr,
    ngx_http_lua_ctx_t **pctx, ngx_http_lua_co_ctx_t **pcoctx);


#endif /* NGX_HTTP_LUA_COROUTINE_H */

