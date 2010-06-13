#ifndef NGX_HTTP_LUA_UTIL_H__
#define NGX_HTTP_LUA_UTIL_H__

#include "ngx_http_lua_common.h"

extern lua_State* ngx_http_lua_new_state();
extern lua_State* ngx_http_lua_new_thread(ngx_http_request_t *r, lua_State *l, int *ref);
extern void ngx_http_lua_del_thread(ngx_http_request_t *r, lua_State *l, int ref, int force_quit);

extern ngx_int_t ngx_http_lua_has_inline_var(ngx_str_t *s);
extern char* ngx_http_lua_rebase_path(ngx_pool_t *pool, ngx_str_t *str);

extern ngx_int_t ngx_http_lua_send_header_if_needed(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx);
extern ngx_int_t ngx_http_lua_send_chain_link(ngx_http_request_t *r, ngx_http_lua_ctx_t *ctx, ngx_chain_t *cl);

#endif

// vi:ts=4 sw=4 fdm=marker

