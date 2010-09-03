/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#ifndef NGX_HTTP_LUA_UTIL_H
#define NGX_HTTP_LUA_UTIL_H

#include "ngx_http_lua_common.h"


lua_State * ngx_http_lua_new_state(ngx_conf_t *cf,
        ngx_http_lua_main_conf_t *lmcf);

lua_State * ngx_http_lua_new_thread(ngx_http_request_t *r, lua_State *l,
        int *ref);
void ngx_http_lua_del_thread(ngx_http_request_t *r, lua_State *l, int ref,
        int force_quit);

ngx_int_t ngx_http_lua_has_inline_var(ngx_str_t *s);
u_char * ngx_http_lua_rebase_path(ngx_pool_t *pool, u_char *src, size_t len);

ngx_int_t ngx_http_lua_send_header_if_needed(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx);
ngx_int_t ngx_http_lua_send_chain_link(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, ngx_chain_t *cl);

ngx_int_t ngx_http_lua_post_request_at_head(ngx_http_request_t *r,
        ngx_http_posted_request_t *pr);

void ngx_http_lua_discard_bufs(ngx_pool_t *pool, ngx_chain_t *in);
ngx_int_t ngx_http_lua_add_copy_chain(ngx_pool_t *pool, ngx_chain_t **chain,
        ngx_chain_t *in);

int ngx_http_lua_var_get(lua_State *L);
int ngx_http_lua_var_set(lua_State *L);


#endif /* NGX_HTTP_LUA_UTIL_H */

