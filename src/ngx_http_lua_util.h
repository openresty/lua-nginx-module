/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef NGX_HTTP_LUA_UTIL_H
#define NGX_HTTP_LUA_UTIL_H

#include "ngx_http_lua_common.h"


#ifndef ngx_str_set
#define ngx_str_set(str, text)                                               \
    (str)->len = sizeof(text) - 1; (str)->data = (u_char *) text
#endif


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
ngx_int_t ngx_http_lua_add_copy_chain(ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, ngx_chain_t **chain, ngx_chain_t *in);
int ngx_http_lua_var_get(lua_State *L);
int ngx_http_lua_var_set(lua_State *L);
void ngx_http_lua_reset_ctx(ngx_http_request_t *r, lua_State *L,
        ngx_http_lua_ctx_t *ctx);
void ngx_http_lua_generic_phase_post_read(ngx_http_request_t *r);
void ngx_http_lua_request_cleanup(void *data);
ngx_int_t ngx_http_lua_run_thread(lua_State *L, ngx_http_request_t *r,
        ngx_http_lua_ctx_t *ctx, int nret);
ngx_int_t ngx_http_lua_wev_handler(ngx_http_request_t *r);
void ngx_http_lua_inject_log_consts(lua_State *L);
u_char * ngx_http_lua_digest_hex(u_char *dest, const u_char *buf,
        int buf_len);
void ngx_http_lua_dump_postponed(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_flush_postponed_outputs(ngx_http_request_t *r);


#endif /* NGX_HTTP_LUA_UTIL_H */
